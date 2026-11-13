with open("Sources/TabStation/SwitcherView.swift") as f:
    lines = f.readlines()
for i, line in enumerate(lines, 1):
    if "func preferredSize" in line or "func configure" in line:
        print(f"{i}: {line.strip()}")
