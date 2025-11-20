# 🧩 SPI Controller (SystemVerilog)

An **APB-to-SPI Controller** implemented in **SystemVerilog** with a deterministic **testbench** for functional verification using **Synopsys VCS**.  
This project demonstrates register-mapped communication between a processor-like **APB interface** and an **SPI master** controller.

---

## 🏗️ Design Overview

| Module | Description |
|---------|-------------|
| **`spi_ctrl.sv`** | Implements the APB interface and SPI finite-state machine (FSM). Handles address/data loading, chip-select control, and transaction sequencing. |
| **`tb_spi_ctrl.sv`** | Deterministic testbench that drives APB transactions, instantiates a behavioral SPI slave, and verifies four transfers (two writes and two reads). |

### **Key Features**
- Parameterized address and data widths  
- LSB-first SPI shifting protocol  
- Interrupt generation after batch completion  
- Self-checking testbench (no manual waveform checks needed)  
- Compatible with Synopsys VCS and DVE waveform viewer  

---

## ⚙️ Environment and Tools

| Tool | Version / Purpose |
|------|-------------------|
| **Simulator** | Synopsys VCS |
| **Waveform Viewer** | DVE (VPD) or GTKWave (VCD) |
| **Language** | SystemVerilog (IEEE 1800-2017) |
| **Platform** | Linux / Windows (MobaXterm or Git Bash) |

---

## ▶️ How to Build & Run

```bash
make run
