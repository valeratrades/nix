import time
import sys

RATE = 0.995


def type_out_text(text, delay=0.1):
    new_delay = delay
    for char in text:
        sys.stdout.write(char)
        sys.stdout.flush()
        time.sleep(new_delay)
        if char == "\n":
            time.sleep(new_delay * 10)
        new_delay -= new_delay * (1 - RATE) * (new_delay / delay)


if __name__ == "__main__":
    if not sys.stdin.isatty():
        text = sys.stdin.read()
        type_out_text(text)
    else:
        print("No piped input detected. Pipe some text into this script.")
