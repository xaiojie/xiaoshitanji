"""Check profile metric coverage, object image assets, and preserved entry points."""
import json
import re
import struct
from pathlib import Path


root = Path(__file__).resolve().parents[2]
metric_source = (root / "FoodDiary/Features/HealthMetricView.swift").read_text()
metric_enum = metric_source.split("var id:", 1)[0]
expected_metrics = []
for declaration in re.findall(r"^    case (.+)$", metric_enum, re.MULTILINE):
    expected_metrics.extend(name.strip() for name in declaration.split(","))

category_source = (root / "FoodDiary/Features/ProfileHealthCategories.swift").read_text()
metric_groups = category_source.split("var metrics:", 1)[1].split("struct ProfileHealthCategoryView", 1)[0]
group_declarations = re.findall(r"case \.(\w+): \[([^\]]*)\]", metric_groups)
categorized_metrics = []
for category, declaration in group_declarations:
    categorized_metrics.extend(re.findall(r"\.(\w+)", declaration))
assert len(categorized_metrics) == len(set(categorized_metrics)), "Duplicate metric categories"
assert set(categorized_metrics) == set(expected_metrics), "Missing health metric category"
print(f"PASS All {len(expected_metrics)} health metrics belong to exactly one category")

source_files = [
    "FoodDiary/App/Theme.swift",
    "FoodDiary/Features/HealthMetricView.swift",
    "FoodDiary/Features/ProfileView.swift",
    "FoodDiary/Features/ProfileHealthCategories.swift",
]
assets = set()
for filename in source_files:
    source = (root / filename).read_text()
    assets.update(re.findall(r'"((?:Food|Health|Profile)[A-Z][A-Za-z0-9]*)"', source))

for name in sorted(assets):
    directory = root / "FoodDiary/Assets.xcassets" / f"{name}.imageset"
    contents = json.loads((directory / "Contents.json").read_text())
    for entry in contents["images"]:
        if "filename" not in entry:
            continue
        image = (directory / entry["filename"]).read_bytes()
        assert image[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG {name}"
        assert struct.unpack(">II", image[16:24]) == (256, 256), f"Unexpected dimensions {name}"
        assert image[25] in (4, 6), f"Missing alpha channel {name}"
print(f"PASS All {len(assets)} referenced object images are 256x256 with alpha")

profile_source = (root / "FoodDiary/Features/ProfileView.swift").read_text()
entry_identifiers = [
    "editProfile", "generalSettings", "wellnessReview", "workoutsEntry",
    "observationInsight", "keepGoingEntry", "cloudSyncEntry",
    "profileEnergyGoal", "profileDietIntake",
]
for identifier in entry_identifiers:
    assert f'"{identifier}"' in profile_source, f"Missing profile action {identifier}"
print("PASS Existing profile actions have retained entry identifiers")
