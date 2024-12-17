# Energy Efficiency Analysis of BLE Heart Rate Bioimplant Sensors with Wake-Up Radios (WuRs)

This repository contains **simulation models** and **power consumption analysis scripts** for evaluating the energy efficiency of **Bluetooth Low Energy (BLE)** heart rate bioimplant sensors integrated with **Wake-Up Radios (WuRs)**. The focus is on three configurations:  

1. **Standalone Duty-Cycled BLE**  
2. **Always-On WuR Integrated with BLE**  
3. **Duty-Cycled WuR Integrated with BLE**  

The scripts facilitate simulation, power computation, and energy comparison to identify the most energy-efficient configuration for BLE-enabled bioimplant sensors.

---

## **Repository Structure**

| **File Name**            | **Description**                                                                 |
|---------------------------|-------------------------------------------------------------------------------|
| `dutyCycled_WuR.m`       | MATLAB script for simulating the **Duty-Cycled WuR Integrated BLE Sensor**. It models periodic wake-ups and wake-up signal (WuS) detection to optimize energy consumption. |
| `alwaysOnWuR.m`          | MATLAB script for simulating the **Always-On WuR Integrated BLE Sensor**. The WuR continuously listens for WuS to activate the BLE module. |
| `dutyCycledBLE`          | MATLAB script for simulating the **Standalone Duty-Cycled BLE Sensor**. BLE alternates between active communication and sleep states to conserve energy. |
| `dcw_powerCompute.py`    | Python script for computing **power consumption** of the **Duty-Cycled WuR Integrated BLE Sensor**. Outputs power and energy usage based on operational states. |
| `aow_powerCompute.py`    | Python script for computing **power consumption** of the **Always-On WuR Integrated BLE Sensor**. Analyzes energy usage for continuous listening and BLE activations. |
| `dcb_powerCompute.py`    | Python script for computing **power consumption** of the **Standalone Duty-Cycled BLE Sensor**. Captures energy trends based on periodic wake-ups and transmissions. |
| `energyComparison.py`    | Python script to **compute and plot cumulative energy consumption** for all three configurations. It compares the total energy usage and visualizes energy efficiency over time. |

---

## **Dependencies**

To run the simulations and analysis scripts, the following software and libraries are required:

1. **MATLAB**:
   - Version **R2019a** through **R2021b**.  
   - Communications Toolbox™ Library for the Bluetooth® Protocol is required.  

2. **Python**:
   - Version **3.8 or higher**.  
   - Required Python Libraries:
     - `matplotlib` (for plotting)  
     - `pandas` (for CSV handling)  
     - `numpy` (for calculations)  

Install the Python libraries using:
```bash
pip install matplotlib pandas numpy

## **Contributors**

Samuel Kodi - skodi001@st.ug.edu.gh
Ferdinand Katsriku - fkatsriku@ug.edu.gh

## **License**
This project is licensed under the MIT License. See the LICENSE file for details.

## **References**
For more details, refer to the associated research manuscript:
Kodi, S., & Katsriku, F.
"Software Simulation Analysis of Integrating a Wake-Up Radio with a Bluetooth Low Energy Heart Rate Implant Sensor."

