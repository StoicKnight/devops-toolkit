import json
from typing import Any, Dict, List, Tuple


def parse_version(version_str: str) -> Tuple[int, int]:
    parts = version_str.split(".")
    major = int(parts[0])
    minor = int(parts[1]) if len(parts) > 1 else 0
    return major, minor


def filter_by_version(
    max_version: str, minion_data: Dict[str, Any]
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[str]]:
    max_version_major, max_version_minor = parse_version(max_version)
    all_minions = minion_data.items()
    unresponsive_minions = list(
        map(
            lambda item: item[0],
            filter(lambda item: "saltversion" not in item[1], all_minions),
        )
    )

    responsive_minions = list(
        filter(lambda item: "saltversion" in item[1], all_minions)
    )
    parsed_minions = list(
        map(
            lambda item: (item[0], parse_version(item[1].get("saltversion"))),
            responsive_minions,
        )
    )
    updatable_minions = list(
        map(
            lambda item: {item[0]: f"{item[1][0]}.{item[1][1]}"},
            filter(
                lambda item: item[1][0] < max_version_major
                and item[1][1] < max_version_minor,
                parsed_minions,
            ),
        )
    )
    higher_version_minions = list(
        map(
            lambda item: {item[0]: f"{item[1][0]}.{item[1][1]}"},
            filter(
                lambda item: item[1][0] == max_version_major
                and item[1][1] > max_version_minor,
                parsed_minions,
            ),
        )
    )

    return updatable_minions, higher_version_minions, unresponsive_minions


def parse_json(filename: str) -> Dict:
    with open(filename, "r") as file:
        data = json.load(file)
    return data


def get_minion_data(files: List[str]) -> List[Dict[str, Any]]:
    return list(map(parse_json, files))


def process_minion_data(max_version: str, data: List[Dict[str, Any]]) -> List:
    return list(map(lambda d: filter_by_version(max_version, d), data))


def generate_report(
    datacenter_name: str,
    updatable: List,
    higher_version: List,
    unresponsive: List,
) -> None:
    """Prints a formatted report for a single datacenter."""
    print(f"\n--- Report for {datacenter_name.upper()} Datacenter ---")

    print(f"\nFound {len(updatable)} minions that need an update:")
    for minion in updatable:
        print(f"  - {minion}")

    print(f"\nFound {len(higher_version)} minions with a higher version:")
    for minion in higher_version:
        print(f"  - {minion}")

    print(f"\nFound {len(unresponsive)} unresponsive minions:")
    for minion_id in unresponsive:
        print(f"  - {minion_id}")
    print("-" * (20 + len(datacenter_name)))


def main():
    JSON_FILES = [
        "all_minion_data1.json",
        "all_minion_data2.json",
        "all_minion_data3.json",
    ]
    MAX_VERSION = "3007.6"

    all_minion_data = get_minion_data(JSON_FILES)
    if not all_minion_data:
        print("No minion data could be processed.")
        return

    processed_data = process_minion_data(MAX_VERSION, all_minion_data)
    for filename, (updatable, higher, unresponsive) in zip(JSON_FILES, processed_data):
        dc_name = filename.split("_")[-1].split(".")[0]
        generate_report(dc_name, updatable, higher, unresponsive)


if __name__ == "__main__":
    main()
