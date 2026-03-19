# Multi-Cycle RISC-V Processor (RV32I) — Verilog

A fully functional multi-cycle RISC-V processor implemented in Verilog, supporting the complete **RV32I Base Integer Instruction Set** (excluding `ecall` and `ebreak`). The design follows a 6-stage FSM-based execution model and exposes a clean memory-mapped bus interface.

---

## Architecture Overview

The processor is built around a **6-stage Finite State Machine**:

```
FETCH → FETCH_WAIT → EXECUTE → MEMREAD → MEMREAD_WAIT → WRITEBACK
```

| State | Description |
|---|---|
| `FETCH` | Assert `mem_rstrb`, send PC on `mem_addr` |
| `FETCH_WAIT` | Wait for memory to return instruction (`mem_rbusy` deasserted) |
| `EXECUTE` | Decode instruction, run ALU, handle stores |
| `MEMREAD` | Assert `mem_rstrb` for load address |
| `MEMREAD_WAIT` | Wait for data memory read to complete |
| `WRITEBACK` | Write result back to register file, advance PC |

---

## Supported Instructions

| Format | Instructions |
|---|---|
| **R-type** | `add`, `sub`, `xor`, `or`, `and`, `sll`, `srl`, `sra`, `slt`, `sltu` |
| **I-type ALU** | `addi`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai`, `slti`, `sltiu` |
| **Load** | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| **Store** | `sb`, `sh`, `sw` |
| **Branch** | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| **Jump** | `jal`, `jalr` |
| **Upper Imm** | `lui`, `auipc` |

---

## Module Breakdown

| Module | Role |
|---|---|
| `riscv_processor` | Top module — FSM + datapath |
| `instr_decoder` | Extracts opcode, rd, rs1, rs2, funct3/7, and instruction-type flags |
| `imm_gen` | Sign-extends immediates for all five formats (I / S / B / J / U) |
| `reg_file` | 32×32-bit register file; x0 hardwired to zero |
| `alu_control` | Maps opcode, funct3, funct7 to an ALU operation code |
| `alu` | Executes ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU, PASS |
| `branch_logic` | Resolves branch taken/not-taken using funct3 and ALU result |
| `load_extractor` | Extracts byte or halfword from a 32-bit word with sign/zero extension |

---

## Getting Started

### Prerequisites
- [iVerilog](https://steveicarus.github.io/iverilog/) (recommended)
- GTKWave (optional, for waveform viewing)

### Run all testbenches
Separately run the three test benches using the following commands
```bash
iverilog -o tb1 Riscv_Processor.v TB_1.v && vvp tb1
```
```bash
iverilog -o tb2 Riscv_Processor.v TB_2.v && vvp tb2
```

```bash
iverilog -o tb3 Riscv_Processor.v TB_3.v && vvp tb3
```

---

## Design Notes

- **Reset** is **active-low** — hold `reset = 0` to reset, release to `1` to run.
- **x0** is hardwired to zero; writes to x0 are silently discarded.
- **JALR** clears the LSB of the computed target address per the RISC-V spec.
- Store instructions wait for `mem_wbusy` to deassert before advancing PC.
- Load/store byte writes replicate the byte across all lanes of `mem_wdata`; `mem_wmask` selects the correct byte(s).

---

## File Structure

```
.
├── Riscv_Processor.v     
├── TB_1.v                
├── TB_2.v                
├── TB_3.v                
└── README.md
```

---

## License

This project was developed as part of a Computer Architecture course assignment.
