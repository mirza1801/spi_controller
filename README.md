# 🧩 SPI Controller (SystemVerilog)

An **APB-to-SPI Controller** implemented in **SystemVerilog** with a deterministic **testbench** for functional verification using **Synopsys VCS**.  
The design demonstrates register-mapped communication between a processor-like APB interface and an SPI master module.

---

## 🏗️ Design Overview
| Module | Description |
|---------|-------------|
| `spi_ctrl.sv` | Implements the APB interface and SPI finite-state machine (FSM). Handles address/data loading, chip-select control, and transfer sequencing. |
| `tb_spi_ctrl.sv` | Testbench that drives APB transactions, instantiates a simple SPI slave model, and verifies four transfers (two writes + two reads). |

**Key features**
- Parameterized address & data width  
- LSB-first SPI shifting  
- Interrupt pulse after each transaction batch  
- Deterministic, self-checking testbench (no manual waveform inspection required)

---

## ⚙️ Environment
- **Simulator:** Synopsys VCS  
- **Waveform Viewer:** DVE (VPD) or GTKWave (VCD)  
- **Language:** SystemVerilog (IEEE 1800-2017)  
- **Platform:** Linux / Windows WSL / MobaXterm  

---

## ▶️ How to Build & Run
```bash
make run

---

## 📊 Simulation Log
[View full log file](docs/spi_ctrl_tb.log)

---

## 🔍 Waveform Screenshot
Captured from Synopsys DVE after successful simulation:

![SPI Waveform](docs/spi_waveform.png)

