# graphify code-graph extractor (github.com/Graphify-Labs/graphify), pinned to v0.9.19
# ponytail: only the tree-sitter grammars packaged in nixpkgs are wired in; graphify
# guards every grammar import with try/except ImportError, so the ~19 grammars missing
# from nixpkgs (go, java, cpp, kotlin, ...) just disable those languages at runtime.
# Add them (or wire uv2nix over the shipped uv.lock) if full language coverage is needed.
final: prev:
{
  graphify = prev.python3Packages.buildPythonApplication {
    pname = "graphify";
    version = "0.9.19";
    pyproject = true;

    src = prev.fetchFromGitHub {
      owner = "Graphify-Labs";
      repo = "graphify";
      tag = "v0.9.19";
      hash = "sha256:0x0am9pgml7p05z8lkl966xzjvghm1ind8ag6khhfbsff57agx8c";
    };

    build-system = [ prev.python3Packages.setuptools ];

    dependencies = with prev.python3Packages; [
      networkx
      numpy
      rapidfuzz
      tree-sitter
      tree-sitter-python
      tree-sitter-javascript
      tree-sitter-rust
      tree-sitter-c-sharp
      tree-sitter-bash
      tree-sitter-json
      tree-sitter-sql
    ];

    # nixpkgs grammar versions drift from graphify's pinned ranges, and 19 declared
    # grammars are absent by design (see header) — the runtime-deps check would reject both.
    dontCheckRuntimeDeps = true;

    pythonImportsCheck = [ "graphify" ];
  };
}
