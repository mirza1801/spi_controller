// Code your design here
// Code your testbench here
// or browse Examples
// Code your design here
module spi_ctrl(  //processor:APB signals
  pclk_i, prst_i, paddr_i, pwdata_i, prdata_o ,penable_i, pready_o, perror_o, pwrite_i,

//main spi

  sclk_o,mosi,miso,ssel,sclk_ref_i,intr_o

);

  parameter ADDR_WIDTH=8;
  parameter DATA_WIDTH=8;
  parameter NUM_TXS=8;  // number of transaction master can do ccontinuesly tif want to do more than that need to reprogram control register 1

  parameter S_IDLE                   = 5'b00001;
  parameter S_ADDR                   = 5'b00010;
  parameter S_IDLE_BW_ADDR_DATA      = 5'b00100;
  parameter S_DATA                   = 5'b01000;
  parameter S_IDLE_WITH_TXS_PENDING  = 5'b10000;



  input  pclk_i, prst_i, penable_i;
  input  pwrite_i;
  input  [ADDR_WIDTH-1:0]  paddr_i;
  input  [DATA_WIDTH-1:0]  pwdata_i;
  output reg [DATA_WIDTH-1:0] prdata_o;
  //spi
  input sclk_ref_i;//refernce clk when no clk btw add and data state
  output reg sclk_o;
  output reg mosi;
  input miso;
  output reg [3:0] ssel;  //slave 4
  output reg pready_o, perror_o;
  integer i,count;
  reg [4:0]state,n_state;
  reg [ADDR_WIDTH-1:0]addr_to_drive;
  reg [DATA_WIDTH-1:0]data_to_drive;
  output reg intr_o; //interrupt after all txs completed to let processor know , it is same as ctrl_regA[7] but define different either one can use
  reg [2:0] next_tx_idx;//what is nxt txs to do
  reg[3:1] num_pending_txs;// to indicate pending txs
  reg [DATA_WIDTH-1:0] collect_slave_data;
  reg sclk_running_f;//this flag is to keep clk from mtr during addr and dta state

  reg[DATA_WIDTH-1:0] collected_slave_data;
  reg[DATA_WIDTH+2-1:0] slave_data_extended;
  reg read_tx_in_progress_f;


    //registers

  reg[ADDR_WIDTH-1:0] addr_regA[NUM_TXS-1:0];//0 to 7 reg number address
  reg[DATA_WIDTH-1:0] data_regA[NUM_TXS-1:0];//10 to 17 h reg number adddress
  reg [DATA_WIDTH-1:0] ctrl_reg;//20 reg address

  //reg programing in the spi master
  always@(posedge pclk_i)begin
    if(prst_i==1) begin
      pready_o=0;
      perror_o=0;
      //sclk_o=1;
      mosi=1;
      intr_o=0;
      collect_slave_data=0;
      count=0;
      state=S_IDLE;
      n_state=S_IDLE;
      ssel=4'b0000;
      for(i=0;i<NUM_TXS;i=i+1)begin
        addr_regA[i]=0;
        data_regA[i]=0;
      end
      ctrl_reg=0;
    end
    else begin
      if (penable_i==1)begin
        pready_o=1;
        if(pwrite_i==1)begin
          if(paddr_i>=8'h00 && paddr_i <=8'h07) begin // means if address fall btw 0 to 7 reg then it will write in that reg same below,data will be write in that addrss range
            addr_regA[paddr_i[2:0]]=pwdata_i;
          end
          else if (paddr_i>=8'h10 && paddr_i <=8'h17) begin
            data_regA[paddr_i[2:0]]=pwdata_i;
          end
          if(paddr_i==8'h20) begin
            ctrl_reg[3:0]=pwdata_i[3:0];//its bcoz;y one register not array of reg and only usng 4 bit 0 to 3 that are one enble bit and 3 no of txs bit define by user and last 4 bits are read only bits
          end

          //read begins
          else begin
             if(paddr_i>=8'h00 && paddr_i <=8'h07) begin // means if address fall btw 0 to 7 reg then it will read from  reg same below,data will be write in that addrss range
              prdata_o= addr_regA[paddr_i[2:0]];
             end
             else if (paddr_i>=8'h10 && paddr_i <=8'h17) begin
               prdata_o=data_regA[paddr_i[2:0]];
             end
             if(paddr_i==8'h20) begin
               prdata_o=ctrl_reg;
             end
             else begin
               pready_o=0;
             end
          end
        end
      end
    end
  end

  // -----------------------------------------------------------------------------
  // NOTE (Understanding FSM prep stage):
  // When ctrl_reg[0] = 1, FSM starts a new SPI transaction.
  // ctrl_reg[6:4] tells which transaction slot (0–7) to use.
  // Example: if ctrl_reg[6:4] = 3'b000 → use addr_regA[0] and data_regA[0]
  //          if ctrl_reg[6:4] = 3'b111 → use addr_regA[7] and data_regA[7]
  // In this stage, no SPI bits are sent yet — FSM just loads data internally:
  //
  //   next_tx_idx   = which transaction number to process
  //   addr_to_drive = address byte copied from addr_regA[next_tx_idx]
  //   data_to_drive = data byte copied from data_regA[next_tx_idx]
  //   count         = bit counter reset to 0
  //ctrl_reg[3:1] = num_txs (set by CPU)
  // number of transfers = num_txs + 1
  // Example:
  //   ctrl_reg[3:1] = 3'b010 → perform 3 transfers (indices 0,1,2)
  // FSM will auto-increment next_tx_idx after each transfer
  // until all num_txs transfers complete, then set intr=1
  //
  // Actual serial transfer happens later in S_ADDR/S_DATA states.
  // -----------------------------------------------------------------------------

  //always@(sclk_ref_i)begin
  //   sclk_o = sclk_running_f ? sclk_ref_i: 1'b1;
  //end

  // (re-enable clocking of sclk_o as a reg; no port type change)
  always @* begin
    sclk_o = sclk_running_f ? sclk_ref_i : 1'b1; //scolk_o should only works at addr and data
  end

  //fsm

  always@(posedge sclk_ref_i)begin
    if(prst_i==0)begin
      case (state)
        S_IDLE:begin
          intr_o=0;
          sclk_running_f=0;
          ctrl_reg[7]=0; //interrupt dont want to active throughtout just after all txs are done;
          if (ctrl_reg[0]==1)begin
            n_state=S_ADDR;
            next_tx_idx=ctrl_reg[6:4];
            num_pending_txs=ctrl_reg[3:1]+1;// no of txs to do;
            addr_to_drive=addr_regA[next_tx_idx];
            data_to_drive=data_regA[next_tx_idx];
            count=0;
          end
        end

        //nxt state

        S_ADDR:begin
          sclk_running_f=1;
          mosi=addr_to_drive[count];//lsb is driven first
          count=count+1;
          if(count==8) begin
            n_state=S_IDLE_BW_ADDR_DATA;
            count=0;
          end
        end


        //nxt state
        S_IDLE_BW_ADDR_DATA:begin  //wait time btw address and data transfer
          sclk_running_f=0;
          count=count+1;
          if(count==4)begin
            n_state=S_DATA;
            count=0;
          end
        end



         //nxt state
        S_DATA:begin //read or write data from or to slave
          sclk_running_f=1;
          if(addr_to_drive[7]==1)begin //write
            mosi=data_to_drive[count];
          end
          if(addr_to_drive[7]==0)begin
            //collect_slave_data[count]=miso;
            slave_data_extended[count]=miso;
            collect_slave_data={miso,collect_slave_data[7:1]};
          end
          count=count+1;
          if(count==8)begin
                      if(addr_to_drive[7]==0)begin
                       // $display("%t:read_data=%h",$time,collect_slave_data); //printing whatever data is collected by design
                        read_tx_in_progress_f=1;
                      end

            num_pending_txs=num_pending_txs-1;
            ctrl_reg[6:4]=ctrl_reg[6:4]+1;//increament nxt txs index design internally update this and it is read only bit
            ctrl_reg[0]=0; //when done with txs making enable 0
            ctrl_reg[3:1]=0;// no.to is also 0
            count=0;
            addr_to_drive=0;
            data_to_drive=0;
            if(num_pending_txs==0)begin
              n_state=S_IDLE;
              ctrl_reg[7]=1;//all the txs completed ,high the interrupt
              intr_o=1; // same as ctrl_reg[7]
            end
            else begin
              n_state=S_IDLE_WITH_TXS_PENDING;
            end
          end
        end

        S_IDLE_WITH_TXS_PENDING:begin
          //pblm while reading is first 2 bits are collecting is invalid bits,getting slip,and getting by the time moved to idle state,to solve this we are collecting even 2 cycle going to idle state
          if(count<2 && read_tx_in_progress_f) begin
           // slave_data_extended[count+8]=miso;
            collect_slave_data={miso,collect_slave_data[7:1]};
            if(count==1) begin
              //$display("%t:read_data=%h\n",$time,slave_data_extended[9:2]);
              $display("%t:read_data=%h\n",$time,collect_slave_data);
              read_tx_in_progress_f=0;
            end
          end
          sclk_running_f=0;
          count=count+1;
          if(count==8)begin
            n_state=S_ADDR;
            next_tx_idx=ctrl_reg[6:4];//getting nxt txs  index which is increamented in S_DATA
            addr_to_drive=addr_regA[next_tx_idx];
            data_to_drive=data_regA[next_tx_idx];
            count=0;
          end
        end
      endcase
    end
  end


  always@(n_state)
    state=n_state;

endmodule