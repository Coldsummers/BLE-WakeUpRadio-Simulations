import pandas as pd
import matplotlib.pyplot as plt

# Function to calculate cumulative energy consumption (in mA·s or Joules)
def calculate_cumulative_energy(time_values, power_values, voltage=3.3):
    """
    Calculate cumulative energy consumption over time.
    time_values: list or array of time values (seconds)
    power_values: list or array of power values in mA
    voltage: operating voltage (default is 3.3V)
    Returns: cumulative energy consumption (list in Joules or mA·s)
    """
    cumulative_energy = [0]  # Start with 0 cumulative energy
    total_energy = 0
    for i in range(1, len(time_values)):
        time_interval = time_values[i] - time_values[i - 1]
        power_watts = (power_values[i] / 1000) * voltage  # Convert mA to W
        energy_joules = power_watts * time_interval
        total_energy += energy_joules
        cumulative_energy.append(total_energy)
    return cumulative_energy

# Load CSV files
def load_csv(file_path):
    """
    Load a CSV file and return the time and power values.
    """
    try:
        data = pd.read_csv(file_path, encoding='utf-8')  # First attempt with utf-8
    except UnicodeDecodeError:
        data = pd.read_csv(file_path, encoding='ISO-8859-1')  # Fallback to ISO-8859-1 encoding
    time_values = data['Time (s)'].values
    power_values = data['BLE Power (mA)'].values
    return time_values, power_values

# File paths for the CSV files
base_dir = os.path.dirname(os.path.abspath(__file__))

always_on_wur_file = os.path.join(base_dir, 'alwaysonwur.csv')
duty_cycled_wur_file = os.path.join(base_dir, 'dutycycledwur.csv')
duty_cycled_ble_file = os.path.join(base_dir, 'dutycycledble.csv')

# Load data from the CSV files
time_always_on_wur, power_always_on_wur = load_csv(always_on_wur_file)
time_duty_cycled_wur, power_duty_cycled_wur = load_csv(duty_cycled_wur_file)
time_duty_cycled_ble, power_duty_cycled_ble = load_csv(duty_cycled_ble_file)

# Calculate cumulative energy consumption for each approach
cumulative_energy_always_on_wur = calculate_cumulative_energy(time_always_on_wur, power_always_on_wur)
cumulative_energy_duty_cycled_wur = calculate_cumulative_energy(time_duty_cycled_wur, power_duty_cycled_wur)
cumulative_energy_duty_cycled_ble = calculate_cumulative_energy(time_duty_cycled_ble, power_duty_cycled_ble)

# Print the total cumulative energy consumption for each scenario
print(f'Total Cumulative Energy for Always-On WUR: {cumulative_energy_always_on_wur[-1]:.6f} J')
print(f'Total Cumulative Energy for Duty-Cycled WUR: {cumulative_energy_duty_cycled_wur[-1]:.6f} J')
print(f'Total Cumulative Energy for Duty-Cycled BLE: {cumulative_energy_duty_cycled_ble[-1]:.6f} J')

# Plot individual cumulative energy consumption over time for comparison
# Plot individual graphs for each energy consumption scenario
plt.figure(figsize=(10, 6))
plt.plot(time_always_on_wur, cumulative_energy_always_on_wur, label='Always-On WUR', color='blue')
plt.xlabel('Time (s)')
plt.ylabel('Cumulative Energy (Joules)')
plt.title('Cumulative Energy Consumption Over Time - Always-On WUR')
plt.grid(True)
plt.tight_layout()
plt.show()

plt.figure(figsize=(10, 6))
plt.plot(time_duty_cycled_wur, cumulative_energy_duty_cycled_wur, label='Duty-Cycled WUR', color='green')
plt.xlabel('Time (s)')
plt.ylabel('Cumulative Energy (Joules)')
plt.title('Cumulative Energy Consumption Over Time - Duty-Cycled WUR')
plt.grid(True)
plt.tight_layout()
plt.show()

plt.figure(figsize=(10, 6))
plt.plot(time_duty_cycled_ble, cumulative_energy_duty_cycled_ble, label='Duty-Cycled BLE', color='orange')
plt.xlabel('Time (s)')
plt.ylabel('Cumulative Energy (Joules)')
plt.title('Cumulative Energy Consumption Over Time - Duty-Cycled BLE')
plt.grid(True)
plt.tight_layout()
plt.show()

# Plot combined cumulative energy consumption over time for comparison
plt.figure(figsize=(10, 6))
plt.plot(time_always_on_wur, cumulative_energy_always_on_wur, label='Always-On WUR', color='blue')
plt.plot(time_duty_cycled_wur, cumulative_energy_duty_cycled_wur, label='Duty-Cycled WUR', color='green')
plt.plot(time_duty_cycled_ble, cumulative_energy_duty_cycled_ble, label='Duty-Cycled BLE', color='orange')
plt.xlabel('Time (s)')
plt.ylabel('Cumulative Energy (Joules)')
plt.title('Cumulative Power Consumption Over Time')
plt.legend()
plt.grid(True)
plt.tight_layout()
plt.show()

# Bar chart for total energy consumption comparison
plt.figure(figsize=(6, 4))
scenarios = ['Always-On WUR', 'Duty-Cycled WUR', 'Duty-Cycled BLE']
energies = [cumulative_energy_always_on_wur[-1], cumulative_energy_duty_cycled_wur[-1], cumulative_energy_duty_cycled_ble[-1]]  # Total energies at the end
plt.bar(scenarios, energies, color=['blue', 'green', 'orange'])
plt.ylabel('Total Energy (J)')
plt.title('Total Energy Consumption Comparison')
plt.tight_layout()
plt.show()
