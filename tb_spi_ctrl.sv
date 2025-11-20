// tb_spi_ctrl.sv
`timescale 1ns/1ps

module tb_spi_ctrl;

  // ---------------- Clocks & Reset ----------------
  logic pclk, prst_n;
  logic sclk_ref;
  initial begin
    pclk = 0;
    forever #5 pclk = ~pclk;       // 100 MHz APB clock
  end

  initial begin
    sclk_ref = 0;
    forever #4 sclk_ref = ~sclk_ref; // 125 MHz SCLK reference (gated in DUT)
  end

  // active-high reset as in DUT
  logic prst;
  initial begin
    prst   = 1'b1;
    prst_n = 1'b0;
    repeat (5) @(negedge pclk);
    prst   = 1'b0;
    prst_n = 1'b1;
  end

  // ---------------- APB-like signals ----------------
  logic        penable, pwrite;
  logic [7:0]  paddr;
  logic [7:0]  pwdata;
  wire  [7:0]  prdata;
  wire         pready, perror;
  wire         intr;

  // ---------------- SPI signals ----------------
  wire         sclk_o;
  wire         mosi;
  logic        miso;
  wire  [3:0]  ssel;

  // ---------------- DUT ----------------
  spi_ctrl dut (
    .pclk_i   (pclk),
    .prst_i   (prst),
    .paddr_i  (paddr),
    .pwdata_i (pwdata),
    .prdata_o (prdata),
    .penable_i(penable),
    .pready_o (pready),
    .perror_o (perror),
    .pwrite_i (pwrite),
    .sclk_o   (sclk_o),
    .mosi     (mosi),
    .miso     (miso),
    .ssel     (ssel),
    .sclk_ref_i(sclk_ref),
    .intr_o   (intr)
  );

  // ---------------- Simple SPI Slave Model ----------------
  //  - 128x8 memory
  //  - Address phase: 8 bits LSB-first on MOSI; MSB=1 => WRITE, MSB=0 => READ
  //  - Data phase: for READ, slave drives mem[addr] (LSB-first) on MISO
  //               for WRITE, slave captures MOSI and writes to mem[addr]
  //
  typedef enum logic [1:0] {SLV_IDLE, SLV_ADDR, SLV_GAP, SLV_DATA} slv_state_e;
  slv_state_e slv_state;
  logic [7:0] mem [0:127];

  // init some memory so READs return non-zero values
  initial begin
    integer i;
    for (i=0;i<128;i++) mem[i] = 8'h00;
    mem[7'd2] = 8'h55;  // will be READ #1
    mem[7'd4] = 8'hC3;  // will be READ #2
  end

  logic [7:0] addr_shift;
  logic [7:0] data_shift;
  integer     bitcnt;
  integer     gapcnt;

  initial begin
    slv_state = SLV_IDLE;
    addr_shift = '0;
    data_shift = '0;
    bitcnt = 0;
    gapcnt = 0;
    miso = 1'b0;
  end

  // Detect the start of an active transfer: sclk_o stops being constantly '1'
  always @(negedge sclk_o) begin
    if (slv_state == SLV_IDLE) begin
      slv_state <= SLV_ADDR;
      bitcnt    <= 0;
    end
  end

  // Capture address bits on rising edge (sample)
  always @(posedge sclk_o) begin
    case (slv_state)
      SLV_ADDR: begin
        addr_shift[bitcnt] <= mosi; // LSB-first
        bitcnt <= bitcnt + 1;
        if (bitcnt == 7) begin
          slv_state <= SLV_GAP;
          bitcnt    <= 0;
          gapcnt    <= 0;
        end
      end
      SLV_DATA: begin
        if (addr_shift[7]) begin
          // WRITE: sample MOSI as data
          data_shift[bitcnt] <= mosi; // LSB-first
          bitcnt <= bitcnt + 1;
          if (bitcnt == 7) begin
            mem[addr_shift[6:0]] <= data_shift;
            slv_state <= SLV_IDLE;
            bitcnt    <= 0;
          end
        end
      end
      default: ;
    endcase
  end

  // Drive data on falling edge so DUT can sample on the next rising edge
  always @(negedge sclk_o) begin
    case (slv_state)
      SLV_GAP: begin
        // During the 4-cycle idle gap (sclk_o held high) we count on sclk_ref edges.
        // When sclk_o falls again, first negedge after the gap will move to DATA.
      end
      SLV_DATA: begin
        if (!addr_shift[7]) begin
          // READ: drive LSB-first
          miso   <= mem[addr_shift[6:0]][bitcnt];
          bitcnt <= bitcnt + 1;
          if (bitcnt == 7) begin
            slv_state <= SLV_IDLE;
            bitcnt    <= 0;
          end
        end
      end
      default: ;
    endcase
  end

  // Count the 4 "idle" reference cycles between address and data (DUT gates SCLK high)
  always @(posedge sclk_ref) begin
    if (slv_state == SLV_GAP) begin
      if (sclk_o == 1'b1) begin
        gapcnt <= gapcnt + 1;
        if (gapcnt == 3) begin
          slv_state <= SLV_DATA;
          gapcnt    <= 0;
          bitcnt    <= 0;
          // Prepare data for READ phase
          if (!addr_shift[7]) begin
            miso <= mem[addr_shift[6:0]][0];
          end
        end
      end
    end
  end

  // ---------------- APB helper tasks ----------------
  task automatic apb_write(input [7:0] addr, input [7:0] data);
    @(negedge pclk);
    paddr  <= addr;
    pwdata <= data;
    pwrite <= 1'b1;
    penable<= 1'b0;

    @(negedge pclk);
    penable<= 1'b1;

    // Wait for ready (single-cycle in this DUT once PENABLE=1)
    @(posedge pclk);
    // optional: assert(pready);

    @(negedge pclk);
    penable<= 1'b0;
    pwrite <= 1'b0;
  endtask

  task automatic apb_read(input [7:0] addr, output [7:0] data);
    @(negedge pclk);
    paddr  <= addr;
    pwrite <= 1'b0;
    penable<= 1'b0;

    @(negedge pclk);
    penable<= 1'b1;

    @(posedge pclk);
    data = prdata;

    @(negedge pclk);
    penable<= 1'b0;
  endtask

  // ---------------- Test sequence ----------------
  // Four transfers total (two WRITEs, two READs).
  //  idx0: WRITE mem[1] <= 8'hA5      (addr byte = 8'b1_0000001 = 0x81)
  //  idx1: WRITE mem[3] <= 8'h3C      (addr byte = 8'b1_0000011 = 0x83)
  //  idx2: READ  mem[2] => expect 0x55 (preset above, addr byte = 0x02)
  //  idx3: READ  mem[4] => expect 0xC3 (preset above, addr byte = 0x04)
  //
  // ctrl_reg map (writes): [3:1]=N transfers-1; [0]=start
  // For 4 transfers, write 4-1=3 to [3:1] and pulse [0]=1.
  //
  logic [7:0] rdata;
  initial begin
    // default drive
    paddr   = '0; pwdata = '0; pwrite = 0; penable = 0;

    // VCD
    $dumpfile("spi_ctrl_tb.vcd");
    $dumpvars(0, tb_spi_ctrl);

    // Wait for reset deassertion
    @(negedge prst);

    // Program address and data arrays
    apb_write(8'h00 + 8'd0, 8'h81); // addr_regA[0] -> WRITE to mem[1]
    apb_write(8'h10 + 8'd0, 8'hA5); // data_regA[0]

    apb_write(8'h00 + 8'd1, 8'h83); // addr_regA[1] -> WRITE to mem[3]
    apb_write(8'h10 + 8'd1, 8'h3C); // data_regA[1]

    apb_write(8'h00 + 8'd2, 8'h02); // addr_regA[2] -> READ  from mem[2]
    // data_regA[2] ignored for reads but we can leave at 0
    apb_write(8'h00 + 8'd3, 8'h04); // addr_regA[3] -> READ  from mem[4]

    // Fire 4 back-to-back transfers: [3:1]=3, [0]=1
    apb_write(8'h20, 8'b0000_1111);

    // Wait for interrupt indicating batch is done
    wait(intr === 1'b1);

    // Optional: read back ctrl_reg (intr_ro|next_idx_ro|ctrl[3:0])
    apb_read(8'h20, rdata);
    $display("[%0t] CTRL readback after batch: 0x%02h", $time, rdata);

    // Report what the slave has now
    $display("[%0t] SLAVE mem[1]=0x%02h (expect A5)", $time, mem[7'd1]);
    $display("[%0t] SLAVE mem[3]=0x%02h (expect 3C)", $time, mem[7'd3]);

    // We cannot read DUT's collected read data via APB; for sanity we show what
    // the slave drove on MISO by echoing mem[2] and mem[4].
    $display("[%0t] READ returned (from slave model): mem[2]=0x%02h, mem[4]=0x%02h",
             $time, mem[7'd2], mem[7'd4]);

    // Short grace period, then finish
    repeat (20) @(negedge pclk);
    $finish;
  end

endmodule
