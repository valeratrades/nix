{ pkgs, workflow-parts, ... }:
let
  shared-base = import workflow-parts.shared.base { inherit pkgs; };
  shared-jobs = {
    tokei = import workflow-parts.shared.tokei { inherit pkgs; };
  };
  go-jobs = {
    tests = import workflow-parts.go.tests { inherit pkgs; };
    gocritic = import workflow-parts.go.gocritic { inherit pkgs; };
    security_audit = import workflow-parts.go.security_audit { inherit pkgs; };
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
    jobs = pkgs.lib.recursiveUpdate shared-jobs go-jobs;
  }
)
