import pyshark
import matplotlib.pyplot as plt
import re
import csv  

# Constants for power consumption (in Amperes)
POWER_PARAMS = {
    'transmit': 3.4e-3,    # BLE transmit power
    'receive': 3.7e-3,     # BLE receive power
    'BLE_idle': 1.5e-6     # BLE idle/sleep power (1.5 µA)
}

V_OP = 3.0  # Coin battery voltage (Volts)

SLEEP_DURATION = 10  # Fixed sleep duration of 10 seconds

# Define a modified packet mapping with improved regex support for event descriptions
PACKET_MAPPING_REGEX = {
    re.compile(r"advertisement indication", re.IGNORECASE): ("LE LL", "Control Opcode: LL_CHANNEL_MAP_IND", 19),
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

# Parse the log file for BLE states with explicit time tracking and sleep power calculation
def parse_log_file(log_file_path):
    events = []
    BLE_times = {'transmit': 0, 'receive': 0, 'idle': 0}
    ble_sleep_phases = 0  # Count the number of sleep phases
    ble_sleep_power_total = 0  # Track total sleep power

    previous_time = None
    with open(log_file_path, 'r') as file:
        for line in file:
            line = line.strip()
            if line.startswith("Time"):
                try:
                    parts = line.split(": ", 1)
                    time_sec = float(parts[0].split()[1].replace('s', ''))
                    description = parts[1].strip()
                    events.append((time_sec, description))

                    if 'Putting BLE device back to sleep after notification.' in description:
                        # Track the number of sleep phases
                        ble_sleep_phases += 1
                        # Calculate sleep power for each 10 second sleep phase
                        sleep_power = SLEEP_DURATION * POWER_PARAMS['BLE_idle'] * 1e6  # µA
                        ble_sleep_power_total += sleep_power

                    if previous_time is not None:
                        duration = time_sec - previous_time

                        # BLE transmit and receive durations
                        if 'transmitting' in description:
                            BLE_times['transmit'] += duration
                        elif 'receiving' in description:
                            BLE_times['receive'] += duration
                        else:
                            BLE_times['idle'] += duration

                    previous_time = time_sec

                except (IndexError, ValueError):
                    continue

    return events, BLE_times, ble_sleep_phases, ble_sleep_power_total

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

def calculate_power(log_events, packet_lengths, N_channels, t_comm, BLE_times, ble_sleep_power_total):
    power_times = {}
    total_power_BLE = 0
    power_per_packet = {}

    packet_counter = 1  # Packet counter to track .pcap file

    for i, event in enumerate(log_events):
        time_sec, desc = event
        power = 0
        packet_length, protocol, operation = match_event_to_packet(desc, packet_lengths, packet_counter)

        if 'BLE device is waking up to send heart rate measurement notification' in desc:
            continue

        if packet_length:
            if 'transmitting' in desc:
                # Include N_channels in the power calculation
                power = (POWER_PARAMS['transmit'] * packet_length * N_channels * V_OP) / t_comm
            elif 'receiving' in desc:
                power = (POWER_PARAMS['receive'] * packet_length * N_channels * V_OP) / t_comm

            total_power_BLE += power
            power_per_packet[time_sec] = power
            packet_counter += 1 if packet_length else 0
        else:
            power = POWER_PARAMS['BLE_idle'] * V_OP
            total_power_BLE += power

        power_times[time_sec] = power

    return power_times, total_power_BLE, ble_sleep_power_total, power_per_packet


def print_power_results(total_power_BLE, ble_sleep_phases, ble_sleep_power_total):
    """
    Print the total power consumption for BLE and BLE Sleep in appropriate units.
    """
    # BLE Power in milliamperes (mA)
    print(f'Total Power Consumption (BLE): {total_power_BLE * 1e3:.3f} mA')

    # BLE Sleep Power in microamperes (µA)
    print(f'Number of sleep phases: {ble_sleep_phases}')
    print(f'Total Power Consumption (BLE Sleep): {ble_sleep_power_total:.2f} µA')

def debug_power_times(ble_power_times, power_per_packet):
    """
    Debugging function to print out power times and check for inconsistencies.
    """
    print("\nBLE Power Times (in mA):")
    for time_sec, power in ble_power_times.items():
        print(f"Time {time_sec}s: {power:.6f} mA")

    print("\nPower Per Packet (in mA):")
    for time_sec, power in power_per_packet.items():
        print(f"Packet Time {time_sec}s: {power:.6f} mA")

def plot_power_consumption(ble_power_times, power_per_packet):
    """
    Plots BLE power consumption on the timeline with annotations for packets.
    """
    # Extract times and corresponding power values for BLE
    ble_times = sorted(ble_power_times.keys())
    ble_powers = [ble_power_times.get(t, 0) for t in ble_times]

    # Create plot for BLE power consumption
    plt.figure(figsize=(10, 5))

    # Plot BLE power consumption
    plt.plot(ble_times, ble_powers, marker='o', linestyle='-', color='b', label="BLE Power")
    plt.title('BLE Power Consumption Over Time')
    plt.xlabel('Time (s)')
    plt.ylabel('Power (mA)')
    plt.ylim(0, max(ble_powers) * 1.2)  # Adjust based on BLE power range
    plt.grid(True)
    
    plt.tight_layout()
    plt.show()

def save_power_to_csv(filename, ble_power_times, power_per_packet):
    """
    Save BLE power consumption data into CSV format.
    """
    with open(filename, 'w', newline='') as csvfile:
        fieldnames = ['Time (s)', 'BLE Power (mA)', 'Power Per Packet (mA)']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for time_sec in sorted(ble_power_times.keys()):
            writer.writerow({
                'Time (s)': time_sec,
                'BLE Power (mA)': f"{ble_power_times.get(time_sec, 0):.6f}",
                'Power Per Packet (mA)': f"{power_per_packet.get(time_sec, 0):.6f}"
            })

    print(f"Power consumption data saved to {filename}")

# Main execution (ensure this code is executed after parsing and calculations)
base_dir = os.path.dirname(os.path.abspath(__file__))

log_file_path = os.path.join(base_dir, 'dcbstate_log.txt')
pcap_file_path = os.path.join(base_dir, 'HeartRateImplant(2).pcap')

log_events, BLE_times, ble_sleep_phases, ble_sleep_power_total = parse_log_file(log_file_path)
packet_lengths = parse_pcap_file(pcap_file_path)

t_comm = 10  # Communication time window (assumed value)
N_channels = 7  # BLE default

ble_power_times, total_power_BLE, ble_sleep_power_total, power_per_packet = calculate_power(
    log_events, packet_lengths, N_channels, t_comm, BLE_times, ble_sleep_power_total
)

csv_filename = os.path.join(base_dir, 'dutycycledble.csv')
save_power_to_csv(csv_filename, ble_power_times, power_per_packet)

print_power_results(total_power_BLE, ble_sleep_phases, ble_sleep_power_total)
debug_power_times(ble_power_times, power_per_packet)
plot_power_consumption(ble_power_times, power_per_packet)
