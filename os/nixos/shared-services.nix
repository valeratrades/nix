{ config, pkgs, lib, user, mylib, inputs, ... }:

let
  userHome = config.users.users."${user.username}".home;
  redisPort = 49974;
  postgresqlPort = 52362;
in {
  services = {
    fstrim.enable = true;
    getty.autologinUser = user.username;

    redis.servers.default = {
      enable = true;
      port = redisPort;
    };

    postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureUsers = [{
        name = "default";
        ensureClauses = {
          superuser = true;
          login = true;
        };
      }];
      ensureDatabases = [ "default" ];
      authentication = ''
        # TYPE  DATABASE        USER            ADDRESS                 METHOD
        local   all             all                                     trust
        host    all             all             127.0.0.1/32            trust
        host    all             all             ::1/128                 trust
      '';
      settings = {
        port = postgresqlPort;
        log_line_prefix = "[%p] ";
        logging_collector = true;
      };
    };

    clickhouse = {
      enable = true;
    };

    openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = true;
        UseDns = true;
        X11Forwarding = true;
        PermitRootLogin = "yes";
      };
    };
  };

  environment.variables = {
    POSTGRESQL_PORT = postgresqlPort;
    REDIS_PORT = redisPort;
    REDIS_DB = "0";
    ENCRYPTION_KEY = "lwLC4GH5UnAYdmHVyfD9UClbMh/saKnRPS+5nILfV2k=";
  };
}