#!/usr/bin/env python3
# Calculate what gradient7(0.0, 0.0) should return

START_LUMINOSITY = 0.85
end_l = START_LUMINOSITY * 0.4
step = (START_LUMINOSITY - end_l) / 6.0

print(f"START_LUMINOSITY: {START_LUMINOSITY}")
print(f"end_l (= START * 0.4): {end_l}")
print(f"step (= (START - end) / 6): {step}")
print()
print("Luminosity values for each step:")
for i in range(7):
    l = START_LUMINOSITY - step * i
    print(f"  i={i}: l={l:.6f}")
print()
print("Expected hex values (greyscale, chroma=0):")
print("Since chroma=0, these should all be pure grey (R=G=B)")
print("Approximate values based on luminosity:")
for i in range(7):
    l = START_LUMINOSITY - step * i
    # Rough approximation: grey value ≈ luminosity * 255
    approx = int(l * 255)
    print(f"  i={i}: l={l:.6f} ≈ #{approx:02x}{approx:02x}{approx:02x}")
