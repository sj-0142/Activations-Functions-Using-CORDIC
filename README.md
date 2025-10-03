# Pipelined CORDIC Engine for Sigmoid & Tanh Computation  

## Overview  
This project implements a **fully pipelined CORDIC (COordinate Rotation DIgital Computer) engine** in **Verilog HDL** to compute **Sigmoid** and **Tanh** activation functions efficiently on FPGA hardware.  
The design leverages DSP slices, pipeline registers, and polynomial approximation for high throughput, low power, and accurate computation—making it suitable for **machine learning accelerators, neural networks, and real-time embedded systems**.  

---

## Features  
- **Fully Pipelined CORDIC Engine**: Computes hyperbolic functions (`sinh`, `tanh`, `sigmoid`) with high throughput.  
- **Polynomial Approximation Optimization**: Custom `1/cosh(x)` approximation with **Mean Absolute Error (MAE) ≈ 2 × 10⁻⁴**.  
- **Clock Speede**: Achieves a maximum operating frequency of **80 MHz** on Nexys-4 FPGA.  
- **Low Power**: Consumes only **0.021 W dynamic power** and **0.1W of total power**.  
- **Scalable Parameters**: Configurable bit-width (`WIDTH`), fractional precision (`FRAC`), and pipeline depth (`ITER`, `POST_STAGES`).  

---

## Architecture / Design Details  

The design is split into two fully pipelined sections:  

1. **CORDIC Hyperbolic Pipeline**  
   - Iteratively computes `sinh(x)` and `cosh(x)` using shift-add operations and arctanh LUTs.  
   - Fully pipelined for continuous data throughput.  

2. **Post-CORDIC Approximation Pipeline**  
   - Computes final outputs:  
     - **Tanh(x) = sinh(x) × (1 – 0.375x²)**  
     - **Sigmoid(x) = 0.5 × tanh(x/2) + 0.5**
    
        


