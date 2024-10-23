from transformers import pipeline
from datasets import load_dataset
import soundfile as sf
import torch
import sys
import numpy as np
import time

try:
    from icecream import ic
except ImportError:  # Graceful fallback if IceCream isn't installed.
    ic = lambda *a: None if not a else (a[0] if len(a) == 1 else a)  # noqa


def split_text(text: str, max_chunk_size: int = 600) -> list:
    lines = text.splitlines()
    chunks = []
    carried_line = ""

    for line in lines:
        if carried_line:
            line = carried_line + " " + line
            carried_line = ""

        if len(line) <= max_chunk_size:
            chunks.append(line)
        else:
            words = line.split()
            current_chunk = ""

            for word in words:
                if len(current_chunk) + len(word) + 1 <= max_chunk_size:
                    current_chunk += word + " "
                else:
                    chunks.append(current_chunk.strip())
                    current_chunk = word + " "

            if current_chunk:
                if len(current_chunk.strip()) <= max_chunk_size:
                    chunks.append(current_chunk.strip())
                else:
                    carried_line = current_chunk.strip()

    if carried_line:
        chunks.append(carried_line)

    chunks = [chunk for chunk in chunks if chunk]

    return chunks


def synthesise(text: str, output_path: str) -> None:
    text_chunks = split_text(text)

    ic("entering synthesiser")
    synthesiser = pipeline("text-to-speech", model="microsoft/speecht5_tts")
    embeddings_dataset = load_dataset(
        "Matthijs/cmu-arctic-xvectors", split="validation"
    )
    ic("loaded dataset")
    speaker_embedding = torch.tensor(embeddings_dataset[7306]["xvector"]).unsqueeze(0)
    ic("embeddings processed")

    mut_i = 0
    audio_chunks = []
    start_time = time.perf_counter()
    for chunk in text_chunks:
        time_passed = time.perf_counter() - start_time
        est_time = (
            time_passed / (mut_i / (len(text) - mut_i)).__round__()
            if mut_i > 0
            else float("inf")
        )
        sys.stderr.write(
            f"\rSynthesising audio: {mut_i}/{len(text)}\nTime passed: {time_passed.round()}s\nEstimated time to completion: {est_time}s\n"
        )
        mut_i += len(chunk)

        speech = synthesiser(
            chunk, forward_params={"speaker_embeddings": speaker_embedding}
        )
        audio_chunks.append(speech["audio"])

    combined_audio = np.concatenate(audio_chunks)

    sf.write(output_path, combined_audio, samplerate=speech["sampling_rate"])


def print_help():
    help_text = """
    Usage: python script.py <input_txt_file> <output_wav_file>

    Arguments:
    <input_txt_file>  : Path to the input text file (must have .txt extension).
    <output_wav_file> : Path to the output wav file (must have .wav extension).

    Options:
    -h, --help        : Show this help message and exit.
    """
    print(help_text)


test_text = """
Last night I got a sense of confusion. The mix between longs and shorts was pretty balanced. Some of the stories boggle the imagination, with lots of aggressive supposition.With energy hot, one young guy told a fantastic tale about a Malaysian wildcat oil company that had a structure at offshore Borneo, which rivaled the North Sea. Sure! A mutual fund manager told of a new surgical process that cuts the risk of impotence from prostate surgery by 75%. Then there are the usual market-cap-to-eyeballs stories about new and old Internet adventures, and wondrous tales about everything from health-food chains to nanotechnology.
"""


def main() -> None:
    if len(sys.argv) != 3 or sys.argv[1] in ["-h", "--help"]:
        print_help()
        return

    if sys.argv[1] in ["-t", "--test"]:
        synthesise(test_text, sys.argv[2])
        print(f"Speech synthesis complete. Output saved to {sys.argv[2]}")
        return

    source_path = sys.argv[1]
    output_path = sys.argv[2]

    if not source_path.endswith(".txt"):
        print("Error: Input file must have a .txt extension.")
        return

    if not output_path.endswith(".mp3"):
        print("Error: Output file must have a .mp3 extension.")
        return

    try:
        with open(source_path, "r") as f:
            text = f.read().strip()
    except FileNotFoundError:
        print(f"Error: Input file {source_path} not found.")
        return

    synthesise(text, output_path)
    print(f"Speech synthesis complete. Output saved to {output_path}")


if __name__ == "__main__":
    main()
