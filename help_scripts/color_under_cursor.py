import pyautogui
while True:
    x, y = pyautogui.position()
    px = pyautogui.pixel(x, y)
    print(px)

# TODO!: write to buffer.
