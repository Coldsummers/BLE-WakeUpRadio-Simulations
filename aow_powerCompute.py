import pyshark
import matplotlib.pyplot as plt
import csv
import re

# Constants for power consumption (in Amperes)
POWER_PARAMS = {
    'WuR_active': 5.3e-6,  # WuR active power
    'WuR_listen': 2.7e-6,  # WuR listening power
    'WuR_sleep': 0.4e-6,   # WuR sleep power
    'transmit': 3.4e-3,    # BLE transmit power
    'receive': 3.7e-3,     # BLE receive power
    'BLE_idle': 1.5e-6     # BLE idle/sleep power
}

V_OP = 3.0  # Operating voltage (3V for coin battery)

# Define a modified packet mapping with improved regex support for event descriptions
PACKET_MAPPING_REGEX = {
    re.compile(r"advertising indication", re.IGNORECASE): ("LE LL", "Control Opcode: LL_CHANNEL_MAP_IND", 19),
    re.compile(r"connection indication", re.IGNORECASE): ("LE LL", "Control Opcode: LL_CHANNEL_MAP_IND", 39),
    re.compile(r"service discovery request", re.IGNORECASE): ("ATT", "Read By Group Type Request", 20),
    re.compile(r"transmitting service discovery", re.IGNORECASE): ("ATT", "Read By Group Type Response", 21),
    re.compile(r"receiving characteristic discovery request", re.IGNORECASE): ("ATT", "Read By Type Request", 20),
    re.compile(r"transmitting characteristic discovery", re.IGNORECASE): ("ATT", "Read By Type Response", 22),
    re.compile(r"receiving all available characteristic descriptors request", re.IGNORECASE): ("ATT", "Find Information Request", 18),
    re.compile(r"transmitting characteristic descriptor discovery", re.IGNORECASE): ("ATT", "Find Information Response", 19),
    re.compile(r"enable notification request", re.IGNORECASE): ("ATT", "Write Request", 18),
    re.compile(r"enable notifications response", re.IGNORECASE): ("ATT", "Write Response", 14),
    re.compile(r"heart rate measurement notification", re.IGNORECASE): ("ATT", "Handle Value Notification", 22)
}

# Parse the log file for WuR and BLE states with explicit time tracking
def parse_log_file(log_file_path):
    events = []
    WuR_times = {'active': 0, 'listening': 0, 'sleep': 0}
    BLE_times = {'transmit': 0, 'receive': 0, 'idle': 0}
    ble_sleep_periods = []

    previous_time = None
    previous_event = None
    ble_asleep = True  # Start with BLE awake
    ble_sleep_start = 0  # Start BLE sleep tracking
    WuR_state = 'listening'  # Track current WuR state, start in listening mode
    
    with open(log_file_path, 'r') as file:
        for line in file:
            line = line.strip()
            if line.startswith("Time"):
                try:
                    parts = line.split(": ", 1)
                    time_sec = int(parts[0].split()[1].replace('s', ''))
                    description = parts[1].strip()
                    events.append((time_sec, description))

                    if previous_time is not None:
                        duration = time_sec - previous_time

                        # Track WuR times
                        if WuR_state == 'listening':
                            WuR_times['listening'] += duration
                        elif WuR_state == 'active':
                            WuR_times['active'] += duration

                        # WuR transitions to listening state
                        if 'Wake-up radio is checking for a signal' in description:
                            WuR_state = 'listening'
                            # BLE goes to sleep when WuR starts listening
                            if not ble_asleep:
                                ble_asleep = True
                                ble_sleep_start = time_sec
                        
                        # BLE wakes up and starts communicating
                        elif 'BLE device is now awake and communicating' in description:
                            WuR_state = 'sleep'
                            # BLE wakes up, track the sleep period
                            if ble_asleep:
                                ble_asleep = False
                                ble_sleep_periods.append((ble_sleep_start, time_sec))  # Record the sleep period

                        # WuR becomes active on wake-up signal
                        elif 'Wake-up signal detected' in description:
                            WuR_state = 'active'

                        # Track BLE transmit and receive durations
                        if 'transmitting' in previous_event:
                            BLE_times['transmit'] += duration
                        elif 'receiving' in previous_event:
                            BLE_times['receive'] += duration
                        else:
                            BLE_times['idle'] += duration

                    previous_time = time_sec
                    previous_event = description

                except (IndexError, ValueError):
                    continue

    # If BLE is asleep at the end of the log, finalize the sleep period
    if ble_asleep:
        ble_sleep_periods.append((ble_sleep_start, previous_time))

    return events, WuR_times, BLE_times, ble_sleep_periods

def parse_pcap_file(pcap_file_path):
    """
    Parse the pcap file to get the packet numbers and lengths.
    """
    packet_lengths = {}
    cap = pyshark.FileCapture(pcap_file_path)
    for packet in cap:
        try:
            packet_num = int(packet.number)
            length = int(packet.length)
            packet_lengths[packet_num] = length
        except AttributeError:
            continue
    return packet_lengths

def match_event_to_packet(description, packet_lengths, packet_counter):
    """
    Match the log event description to a BLE packet using regex for description matching and length.
    """
    packet_length = packet_lengths.get(packet_counter, None)
    
    # Check for matching event based on description and length
    for regex, (protocol, operation, expected_length) in PACKET_MAPPING_REGEX.items():
        if regex.search(description) and (packet_length and abs(packet_length - expected_length) <= 2):
            return packet_length, protocol, operation
    
    return None, None, None

# Rest of the calculate_power function remains the same
def calculate_power(log_events, packet_lengths, N_channels, t_comm, WuR_times, ble_sleep_periods):
    power_times = {}
    WuR_power_times = {}
    total_power_WuR = 0
    total_power_BLE = 0
    total_ble_sleep_power = 0
    power_per_packet = {}

    # Calculate WuR power consumption
    total_power_WuR = (WuR_times['active'] * POWER_PARAMS['WuR_active'] +
                       WuR_times['listening'] * POWER_PARAMS['WuR_listen'] +
                       WuR_times['sleep'] * POWER_PARAMS['WuR_sleep']) * V_OP

    current_wur_power = POWER_PARAMS['WuR_listen']  # Start WuR in listening state

    # BLE awake tracking
    ble_awake_start_time = None
    ble_awake_end_time = None
    packet_counter = 1  # Packet counter to track .pcap file

    for i, event in enumerate(log_events):
        time_sec, desc = event
        power = 0
        packet_length, protocol, operation = match_event_to_packet(desc, packet_lengths, packet_counter)

        # Assign the correct WuR power state
        if 'Wake-up radio is checking for a signal' in desc:
            current_wur_power = POWER_PARAMS['WuR_listen']
        elif 'BLE device is now awake and communicating' in desc:
            current_wur_power = POWER_PARAMS['WuR_sleep']
            if ble_awake_start_time is None:
                ble_awake_start_time = time_sec
        elif 'Wake-up signal detected' in desc:
            current_wur_power = POWER_PARAMS['WuR_active']

        # Record WuR power over time in microamps for plotting
        WuR_power_times[time_sec] = current_wur_power * 1e6

        # Calculate BLE power consumption
        if packet_length:
            if 'transmitting' in desc:
                power = (POWER_PARAMS['transmit'] * packet_length * N_channels * V_OP) / t_comm
            elif 'receiving' in desc:
                power = (POWER_PARAMS['receive'] * packet_length * N_channels * V_OP) / t_comm

            total_power_BLE += power
            power_per_packet[time_sec] = power

            # Only increment packet counter if a match was found
            packet_counter += 1 if packet_length else 0
        else:
            # Default BLE idle power
            power = POWER_PARAMS['BLE_idle'] * V_OP
            total_power_BLE += power
        
        power_times[time_sec] = power

    # Handle BLE Sleep Periods and calculate BLE sleep power
    for start_time, end_time in ble_sleep_periods:
        sleep_duration = end_time - start_time
        total_ble_sleep_power += sleep_duration * POWER_PARAMS['BLE_idle'] * V_OP

    return power_times, WuR_power_times, total_power_WuR, total_power_BLE, total_ble_sleep_power, power_per_packet

# Function to print power results
def print_power_results(total_power_WuR, total_power_BLE, total_ble_sleep_power):
    """
    Print the total power consumption for WuR, BLE, and BLE Sleep in appropriate units.
    """
    # WuR Power in microamperes (µA)
    print(f'Total Power Consumption (WuR): {total_power_WuR * 1e6:.2f} µA')

    # BLE Power in milliamperes (mA)
    print(f'Total Power Consumption (BLE): {total_power_BLE * 1e3:.3f} mA')

    # BLE Sleep Power in microamperes (µA)
    print(f'Total Power Consumption (BLE Sleep): {total_ble_sleep_power * 1e6:.2f} µA')

# Function to print and debug power times dictionaries
def debug_power_times(ble_power_times, wur_power_times, power_per_packet):
    """
    Debugging function to print out power times and check for inconsistencies.
    """
    print("\nBLE Power Times (in mA):")
    for time_sec, power in ble_power_times.items():
        print(f"Time {time_sec}s: {power:.6f} mA")

    #print("\nWuR Power Times (in µA):")
    #for time_sec, power in wur_power_times.items():
    #    print(f"Time {time_sec}s: {power:.2f} µA")

# Function to plot BLE and WuR power consumption together
def plot_power_consumption(ble_power_times, wur_power_times, power_per_packet):
    """
    Plots BLE and WuR power consumption on the same timeline with annotations for packets.
    """
    # Extract times and corresponding power values for BLE and WuR
    ble_times = sorted(ble_power_times.keys())
    ble_powers = [ble_power_times.get(t, 0) for t in ble_times]

    wur_times = sorted(wur_power_times.keys())
    wur_powers = [wur_power_times.get(t, 0) for t in wur_times]

    # Create subplots: one for BLE power and another for WuR power
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 10))

    # Plot BLE power consumption
    ax1.plot(ble_times, ble_powers, marker='o', linestyle='-', color='b', label="BLE Power")
    ax1.set_title('BLE Power Consumption Over Time')
    ax1.set_xlabel('Time (s)')
    ax1.set_ylabel('Power (mA)')
    ax1.set_ylim(0, max(ble_powers) * 1.2)  # Adjust based on BLE power range
    ax1.grid(True)

    # Plot WuR power consumption
    ax2.plot(wur_times, wur_powers, marker='x', linestyle='-', color='r', label="WuR Power")
    ax2.set_title('WuR Power Consumption Over Time')
    ax2.set_xlabel('Time (s)')
    ax2.set_ylabel('Power (µA)')
    ax2.set_ylim(0, max(wur_powers) * 1.2)  # Adjust based on WuR power range
    ax2.grid(True)

    # Final adjustments to layout and show the plot
    plt.tight_layout()
    plt.show()

def save_power_to_csv(filename, ble_power_times, wur_power_times, power_per_packet):
    with open(filename, 'w', newline='') as csvfile:
        fieldnames = ['Time (s)', 'BLE Power (mA)', 'WuR Power (µA)']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        writer.writeheader()
        all_times = sorted(set(ble_power_times.keys()).union(wur_power_times.keys()))

        for time_sec in all_times:
            writer.writerow({
                'Time (s)': time_sec,
                'BLE Power (mA)': f"{ble_power_times.get(time_sec, 0):.6f}",
                'WuR Power (µA)': f"{wur_power_times.get(time_sec, 0):.2f}"
            })

    print(f"Power consumption data saved to {filename}")

# Main execution (ensure this code is executed after parsing and calculations)
base_dir = os.path.dirname(os.path.abspath(__file__))

log_file_path = os.path.join(base_dir, 'aowstate_log.txt')
pcap_file_path = os.path.join(base_dir, 'HeartRateImplant(1).pcap')
N_channels = 7
t_comm = 10  

log_events, WuR_times, BLE_times, ble_sleep_periods = parse_log_file(log_file_path)
packet_lengths = parse_pcap_file(pcap_file_path)

ble_power_times, wur_power_times, total_power_WuR, total_power_BLE, total_ble_sleep_power, power_per_packet = calculate_power(
    log_events, packet_lengths, N_channels, t_comm, WuR_times, ble_sleep_periods)

csv_filename = os.path.join(base_dir, 'alwaysonwur.csv')
save_power_to_csv(csv_filename, ble_power_times, wur_power_times, power_per_packet)

# Debug the power times dictionaries
debug_power_times(ble_power_times, wur_power_times, power_per_packet)

# Print the power results
print_power_results(total_power_WuR, total_power_BLE, total_ble_sleep_power)

# Plot the integrated BLE and WuR power consumption graphs
plot_power_consumption(ble_power_times, wur_power_times, power_per_packet)
