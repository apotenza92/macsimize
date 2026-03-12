#!/usr/bin/env python3

import argparse
import csv
import json
import os
import platform
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", required=True)
    parser.add_argument("--apps-dir", required=True)
    parser.add_argument("--results-csv", required=True)
    parser.add_argument("--summary-md", required=True)
    parser.add_argument("--gui-plan", required=True)
    parser.add_argument("--gui-results")
    parser.add_argument("--build-identity", default="")
    parser.add_argument("--with-gui", action="store_true")
    return parser.parse_args()


def read_matrix(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def read_probe_results(apps_dir):
    results = {}
    for path in sorted(Path(apps_dir).glob("*.json")):
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
        results[payload["appName"]] = payload
    return results


def read_gui_results(path):
    if not path or not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def highest_risk(samples):
    order = {"low": 0, "medium": 1, "high": 2}
    value = "low"
    for sample in samples:
        if order[sample.get("riskLevel", "low")] > order[value]:
            value = sample["riskLevel"]
    return value


def app_decision(status, samples, gui_rows_for_app=None):
    if status != "ok":
        return "inconclusive"
    gui_rows_for_app = gui_rows_for_app or []
    if any(row.get("pass_fail") == "FAIL" for row in gui_rows_for_app):
        return "needs_follow_up"
    if not samples:
        return "inconclusive"
    risks = {sample["riskLevel"] for sample in samples}
    if "high" in risks:
        return "needs_follow_up"
    if "medium" in risks:
        return "covered_with_risk"
    return "covered"


def build_gui_plan(matrix_rows, probe_results, with_gui):
    plan_rows = []
    seen_family_structures = defaultdict(set)
    expectation_preference = {
        "blank_region_should_maximize": ["left_blank", "left_drag_region", "left_top_strip"],
        "title_or_passive_region_should_maximize": ["center_passive", "center_title", "right_passive", "right_top_strip"],
        "control_should_not_maximize": ["toolbar_control", "control_probe"],
        "tab_should_not_maximize": ["active_tab", "traffic_light_gap"],
        "blank_tabstrip_should_maximize": ["blank_tabstrip", "far_right_top_strip"],
    }
    for row in matrix_rows:
        if row["priority"] == "Skip":
            continue
        probe = probe_results.get(row["app_name"])
        if not probe or probe["status"] != "ok":
            continue
        samples = probe["samples"]
        structures = {sample["structureClass"] for sample in samples}
        family = row["family"]
        risk = highest_risk(samples)
        first_representative = not seen_family_structures[family]
        new_family_structure = any(structure not in seen_family_structures[family] for structure in structures)
        seen_family_structures[family].update(structures)

        should_validate = False
        if with_gui and row["gui_validation"] != "never":
            if row["gui_validation"] == "always":
                should_validate = True
            elif risk == "high":
                should_validate = True
            elif first_representative:
                should_validate = True
            elif row["priority"] == "P0" and new_family_structure:
                should_validate = True

        if not should_validate:
            continue

        chosen = {}
        for sample in samples:
            expectation = sample.get("recommendedGUICheck", "")
            if not expectation:
                continue
            existing = chosen.get(expectation)
            if not existing:
                chosen[expectation] = sample
                continue
            preference = expectation_preference.get(expectation, [])
            sample_rank = preference.index(sample["sampleLabel"]) if sample["sampleLabel"] in preference else len(preference)
            existing_rank = preference.index(existing["sampleLabel"]) if existing["sampleLabel"] in preference else len(preference)
            if sample_rank < existing_rank:
                chosen[expectation] = sample

        for expectation in [
            "blank_region_should_maximize",
            "title_or_passive_region_should_maximize",
            "control_should_not_maximize",
            "tab_should_not_maximize",
            "blank_tabstrip_should_maximize",
        ]:
            sample = chosen.get(expectation)
            if not sample:
                continue
            plan_rows.append(
                {
                    "app_name": row["app_name"],
                    "bundle_id": row["bundle_id"],
                    "family": row["family"],
                    "priority": row["priority"],
                    "prep_mode": row["prep_mode"],
                    "sample_label": sample["sampleLabel"],
                    "screen_x": sample["screenX"],
                    "screen_y": sample["screenY"],
                    "expected_outcome": expectation,
                }
            )
    return plan_rows


def write_gui_plan(path, plan_rows):
    fieldnames = [
        "app_name",
        "bundle_id",
        "family",
        "priority",
        "prep_mode",
        "sample_label",
        "screen_x",
        "screen_y",
        "expected_outcome",
    ]
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(plan_rows)


def gui_results_by_app(gui_rows):
    grouped = defaultdict(list)
    for row in gui_rows:
        grouped[row["app_name"]].append(row)
    return grouped


def write_results_csv(path, matrix_rows, probe_results, gui_rows):
    gui_by_app = gui_results_by_app(gui_rows)
    fieldnames = [
        "record_type",
        "app_name",
        "bundle_id",
        "family",
        "priority",
        "sample_label",
        "screen_x",
        "screen_y",
        "window_frame",
        "hit_role_path",
        "hit_action_path",
        "hit_frame_path",
        "top_container_role",
        "contains_ax_toolbar",
        "contains_axtabgroup",
        "contains_interactive_control",
        "contains_static_text",
        "contains_duplicate_leaf_group",
        "structure_class",
        "risk_level",
        "recommended_gui_check",
        "notes",
        "before_bounds",
        "after_bounds",
        "macsimize_capture_logged",
        "expected_outcome",
        "actual_outcome",
        "pass_fail",
        "app_status",
        "app_decision",
    ]

    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in matrix_rows:
            probe = probe_results.get(row["app_name"])
            status = probe["status"] if probe else "missing_bundle"
            decision = app_decision(status, probe.get("samples", []) if probe else [], gui_by_app.get(row["app_name"], []))
            if not probe or not probe["samples"]:
                writer.writerow(
                    {
                        "record_type": "app",
                        "app_name": row["app_name"],
                        "bundle_id": row["bundle_id"],
                        "family": row["family"],
                        "priority": row["priority"],
                        "app_status": status,
                        "app_decision": decision,
                        "notes": probe.get("notes", "") if probe else "app bundle not found",
                    }
                )
                continue

            for sample in probe["samples"]:
                writer.writerow(
                    {
                        "record_type": "ax",
                        "app_name": row["app_name"],
                        "bundle_id": row["bundle_id"],
                        "family": row["family"],
                        "priority": row["priority"],
                        "sample_label": sample["sampleLabel"],
                        "screen_x": sample["screenX"],
                        "screen_y": sample["screenY"],
                        "window_frame": probe["windowFrame"],
                        "hit_role_path": ">".join(sample["hitRolePath"]),
                        "hit_action_path": ">".join(sample["hitActionPath"]),
                        "hit_frame_path": "|".join(sample["hitFramePath"]),
                        "top_container_role": sample["topContainerRole"],
                        "contains_ax_toolbar": sample["containsAXToolbar"],
                        "contains_axtabgroup": sample["containsAXTabGroup"],
                        "contains_interactive_control": sample["containsInteractiveControl"],
                        "contains_static_text": sample["containsStaticText"],
                        "contains_duplicate_leaf_group": sample["containsDuplicateLeafGroup"],
                        "structure_class": sample["structureClass"],
                        "risk_level": sample["riskLevel"],
                        "recommended_gui_check": sample["recommendedGUICheck"],
                        "notes": sample["notes"],
                        "app_status": status,
                        "app_decision": decision,
                    }
                )

            for gui in gui_by_app.get(row["app_name"], []):
                writer.writerow(
                    {
                        "record_type": "gui",
                        "app_name": row["app_name"],
                        "bundle_id": row["bundle_id"],
                        "family": row["family"],
                        "priority": row["priority"],
                        "sample_label": gui["sample_label"],
                        "screen_x": gui["screen_x"],
                        "screen_y": gui["screen_y"],
                        "before_bounds": gui["before_bounds"],
                        "after_bounds": gui["after_bounds"],
                        "macsimize_capture_logged": gui["macsimize_capture_logged"],
                        "expected_outcome": gui["expected_outcome"],
                        "actual_outcome": gui["actual_outcome"],
                        "pass_fail": gui["pass_fail"],
                        "app_status": status,
                        "app_decision": decision,
                        "notes": gui.get("notes", ""),
                    }
                )


def write_summary(path, matrix_rows, probe_results, gui_rows, build_identity):
    gui_by_app = gui_results_by_app(gui_rows)
    family_groups = defaultdict(list)
    outliers = []
    coverage = {"scanned": 0, "normalized": 0, "gui": 0, "gui_failures": 0, "skipped": 0}

    for row in matrix_rows:
        probe = probe_results.get(row["app_name"])
        status = probe["status"] if probe else "missing_bundle"
        gui_rows_for_app = gui_by_app.get(row["app_name"], [])
        decision = app_decision(status, probe.get("samples", []) if probe else [], gui_rows_for_app)
        family_groups[row["family"]].append((row, probe, decision))
        if row["priority"] == "Skip":
            coverage["skipped"] += 1
            continue
        coverage["scanned"] += 1
        if status == "ok":
            coverage["normalized"] += 1
        if gui_rows_for_app:
            coverage["gui"] += 1
        if any(gui_row.get("pass_fail") == "FAIL" for gui_row in gui_rows_for_app):
            coverage["gui_failures"] += 1
        if decision in {"covered_with_risk", "needs_follow_up", "inconclusive"}:
            outliers.append((row, probe, decision))

    lines = [
        "# Titlebar AX Survey Summary",
        "",
        "## Survey Metadata",
        f"- generated_at_utc: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}",
        f"- macos_version: {platform.mac_ver()[0] or 'unknown'}",
        f"- build_identity: {build_identity or 'unknown'}",
        "",
        "## Coverage Summary",
        f"- apps_scanned: {coverage['scanned']}",
        f"- apps_successfully_normalized: {coverage['normalized']}",
        f"- apps_gui_validated: {coverage['gui']}",
        f"- gui_failures: {coverage['gui_failures']}",
        f"- skipped_apps: {coverage['skipped']}",
        "",
        "## Findings By Family",
    ]

    for family in sorted(family_groups):
        entries = family_groups[family]
        app_names = [row["app_name"] for row, _, _ in entries]
        structures = sorted(
            {
                sample["structureClass"]
                for _, probe, _ in entries
                if probe and probe["status"] == "ok"
                for sample in probe["samples"]
            }
        )
        decisions = sorted({decision for _, _, decision in entries})
        lines.extend(
            [
                f"### {family}",
                f"- representative_apps: {', '.join(app_names)}",
                f"- dominant_structures: {', '.join(structures) if structures else 'none'}",
                f"- survey_decisions: {', '.join(decisions)}",
                "",
            ]
        )

    lines.extend(["## Outliers"])
    if not outliers:
        lines.append("- none")
    else:
        for row, probe, decision in outliers:
            risk = highest_risk(probe.get("samples", [])) if probe else "high"
            note = probe.get("notes", "") if probe else "bundle missing"
            gui_failure = any(gui_row.get("pass_fail") == "FAIL" for gui_row in gui_by_app.get(row["app_name"], []))
            lines.append(
                f"- {row['app_name']}: decision={decision} risk={risk} gui_failure={str(gui_failure).lower()} note={note or 'see CSV rows'}"
            )
    lines.extend(["", "## Candidate Product Work"])

    high_risk_families = sorted(
        {
            row["family"]
            for row, probe, decision in outliers
            if decision == "needs_follow_up"
        }
    )
    if high_risk_families:
        lines.append(f"- app families needing more data: {', '.join(high_risk_families)}")
    else:
        lines.append("- app families needing more data: none identified in this run")
    lines.append("- heuristics to add: only after the same structure appears in multiple apps or a P0 family")
    lines.append("- heuristics to avoid: app-name-specific exceptions unless no structural alternative exists")

    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")


def main():
    args = parse_args()
    matrix_rows = read_matrix(args.matrix)
    probe_results = read_probe_results(args.apps_dir)
    gui_rows = read_gui_results(args.gui_results)
    plan_rows = build_gui_plan(matrix_rows, probe_results, args.with_gui)
    write_gui_plan(args.gui_plan, plan_rows)
    write_results_csv(args.results_csv, matrix_rows, probe_results, gui_rows)
    write_summary(args.summary_md, matrix_rows, probe_results, gui_rows, args.build_identity)


if __name__ == "__main__":
    main()
