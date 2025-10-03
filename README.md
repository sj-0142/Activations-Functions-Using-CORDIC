# Pipelined CORDIC Engine for Sigmoid & Tanh Computation  

## Overview  
This project implements a **fully pipelined CORDIC (COordinate Rotation DIgital Computer) engine** in **Verilog HDL** to compute **Sigmoid** and **Tanh** activation functions efficiently on FPGA hardware.  
The design leverages DSP slices, pipeline registers, and polynomial approximation for high throughput, low power, and accurate computation—making it suitable for **machine learning accelerators, neural networks, and real-time embedded systems**.  

---

## Features  
- **Fully Pipelined CORDIC Engine**: Computes hyperbolic functions (`sinh`, `tanh`, `sigmoid`) with high throughput.  
- **Polynomial Approximation Optimization**: Custom `1/cosh(x)` approximation with **Mean Absolute Error (MAE) ≈ 2 × 10⁻⁴**.  
- **Clock Speed**: Achieves a maximum operating frequency of **80 MHz** on Nexys-4 FPGA.  
- **Low Power**: Consumes only **0.021 W dynamic power** and **0.1W of total power**.  
- **Scalable Parameters**: Configurable bit-width (`WIDTH`), fractional precision (`FRAC`), and pipeline depth (`ITER`, `POST_STAGES`).  

---

### Key Design Parameters

- **Data Width**: 32 bits
- **Fractional Bits**: 14 (Q14 fixed-point format)
- **CORDIC Iterations**: 16
- **Pipeline Stages**: 21 total (16 CORDIC + 5 post-processing for tanh and sigmoid calculation)



---

## Architecture   

The design is split into two fully pipelined sections:  

1. **CORDIC Hyperbolic Pipeline**  
   - Iteratively computes `sinh(x)` and `cosh(x)` using shift-add operations and arctanh LUTs.  
   - Fully pipelined with **16 stages**, one per CORDIC iteration, ensuring continuous data throughput (new input every clock cycle).  
   - **Mathematical Formulation**:  
     - Hyperbolic rotations are based on:  
       ```
       sinh(z + atanh(2⁻ⁱ)) = sinh(z)cosh(atanh(2⁻ⁱ)) + cosh(z)sinh(atanh(2⁻ⁱ))
       cosh(z + atanh(2⁻ⁱ)) = cosh(z)cosh(atanh(2⁻ⁱ)) + sinh(z)sinh(atanh(2⁻ⁱ))
       ```
     - Iterative update equations (fixed-point implementation):  
       ```
       x_{i+1} = x_i + d_i * (y_i >> i)
       y_{i+1} = y_i + d_i * (x_i >> i)
       z_{i+1} = z_i - d_i * atanh(2⁻ⁱ)
       ```
     - Here, `d_i ∈ {+1, -1}` controls the direction of hyperbolic rotation, and the shifts (`>> i`) represent division by powers of two.  

2. **Post-CORDIC Pipeline**  
   - Applies polynomial approximation and scaling to compute the final activation functions.  
   - **Pipeline Stages (5 total):**  
     1. Compute `x²`  
     2. Multiply to get `0.375 × x²`  
     3. Subtract: `1 – (0.375 × x²)`  
     4. Multiply with `sinh(x)` → `tanh(x) = sinh(x) × (1 – 0.375x²)`  
     5. Reverse Q14 fixed-point shift (scaling back to correct format)  
   - Final outputs:  
     - **Tanh(x) ≈ sinh(x) × (1 – 0.375x²)**  
     - **Sigmoid(x) = (tanh(x/2) + 1) / 2**  

---

## Implementation & Tools
 
**Hardware Description Language**: Verilog HDL (Verilog 2001)  
**Synthesis Tool**: Xilinx Vivado Design Suite  
**Target FPGA**: Nexys 4 DDR (Artix-7 XC7A100TCSG324-1)  
**Resource Optimization**: DSP48 slices, Block RAM
    
        


