{ pkgs, workflow-parts, ... }:
let
  shared-base = import workflow-parts.shared.base { inherit pkgs; };
  shared-jobs = {
    tokei = import workflow-parts.shared.tokei { inherit pkgs; };
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
    jobs = shared-jobs;
  }
)
