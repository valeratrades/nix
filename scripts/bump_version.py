import re, typing, argparse  # noqa: E401
from typing import Literal

VersionType = Literal["major", "minor", "patch"]


def get_lines(file_path: str) -> list[str]:
	with open(file_path, "r") as file:
		return file.readlines()


def write_version(file_path: str, version_type: VersionType) -> str:
	pattern = re.compile(r'^version = "([0-9]+)\.([0-9]+)\.([0-9]+)"$')
	lines = get_lines(file_path)
	assert len(lines) > 0
	version = ""
	with open(file_path, "w") as file:
		for line in lines:
			match = pattern.search(line)

			line_to_write = line
			if match:
				major, minor, patch = map(int, match.groups())
				if version_type == "major":
					major += 1
					minor = 0
					patch = 0
				elif version_type == "minor":
					minor += 1
					patch = 0
				elif version_type == "patch":
					patch += 1
				else:
					typing.assert_never(version)
				version = f"{major}.{minor}.{patch}"

				line_to_write = f'version = "{version}"\n'

			file.write(line_to_write)

	return version


def main():
	parser = argparse.ArgumentParser(description="Update version in a pyproject.toml file")
	parser.add_argument("file_path", type=str, help="Path to the file containing the version")
	version_group = parser.add_mutually_exclusive_group(required=True)
	version_group.add_argument("-j", "--major", action="store_const", const="major", dest="version_type", help="Increment the major version")
	version_group.add_argument("-m", "--minor", action="store_const", const="minor", dest="version_type", help="Increment the minor version")
	version_group.add_argument("-p", "--patch", action="store_const", const="patch", dest="version_type", help="Increment the patch version")

	args = parser.parse_args()

	version = write_version(args.file_path, args.version_type)
	assert version != ""
	print(version)


if __name__ == "__main__":
	main()
