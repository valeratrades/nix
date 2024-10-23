import openai
import requests
import json
import sys
import os
import pyperclip

api_key = os.getenv("OPENAI_KEY")
# second var is cost of 1k tokens
gpt35 = ("gpt-3.5-turbo", 0.002)
gpt4t = ("gpt-4-1106-preview", 0.015)  # price is a guess, and is not to be trusted

# ==========================================================
openai.api_type = "azure"
openai.api_key = api_key


def request(language, question, model=gpt35):
    instruction = f"Translate to {language}"

    system_line = {"role": "system", "content": instruction}
    user_line = {"role": "user", "content": question}
    conversation = [system_line] + [user_line]

    url = "https://api.openai.com/v1/chat/completions"
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"}

    data = {
        "model": f"{model[0]}",
        "messages": conversation,
        "temperature": 0,
        # "max_tokens": 100,
    }
    r = requests.post(url, headers=headers, data=json.dumps(data)).json()

    return r["choices"][0]["message"]["content"].split(";")[0]


def main():
    map_language = {
        "-f": "French",
        "-e": "English",
        "-r": "Russian",
    }
    language = map_language.get(sys.argv[1])
    question = " ".join(sys.argv[2:])
    return request(language, question)


if __name__ == "__main__":
    response = main()
    pyperclip.copy(response)
    print(response)
