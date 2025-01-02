{ pkgs, workflow-parts, ... }:
let
  shared-base = import workflow-parts.shared.base { inherit pkgs; };
  shared-jobs = {
    tokei = import workflow-parts.shared.tokei { inherit pkgs; };
  };
  rust-base = import workflow-parts.rust.base { inherit pkgs; };
  rust-jobs = {
    tests = import workflow-parts.rust.tests { inherit pkgs; };
    doc = import workflow-parts.rust.doc { inherit pkgs; };
    miri = import workflow-parts.rust.miri { inherit pkgs; };
    clippy = import workflow-parts.rust.clippy { inherit pkgs; };
    machete = import workflow-parts.rust.machete { inherit pkgs; };
    sort = import workflow-parts.rust.sort { inherit pkgs; };
  };
  base = {
    on = {
      push = { };
      pull_request = { };
      workflow_dispatch = { };
      schedule = [ { cron = "0 0 1 * *"; } ];
    };
  };
in
(pkgs.formats.yaml { }).generate "" (
  pkgs.lib.recursiveUpdate base {
    inherit (shared-base) permissions name;
    inherit (rust-base) env;
    jobs = pkgs.lib.recursiveUpdate (pkgs.lib.recursiveUpdate shared-jobs rust-base.jobs) rust-jobs;
  }
)
