SIMV = simv
SRC  = spi_ctrl.sv tb_spi_ctrl.sv

all: run

compile:
	@vcs -sverilog -full64 -debug_access+all $(SRC) -o $(SIMV)

run: compile
	@./$(SIMV) | tee spi_ctrl_tb.log

waves:
	@dve -vpd spi_ctrl_tb.vpd &

