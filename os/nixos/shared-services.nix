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
      extraServerConfig = ''
        <!-- Disable verbose system logs that cause unnecessary CPU usage -->
        <asynchronous_metric_log remove="1"/>
        <metric_log remove="1"/>
        <trace_log remove="1"/>
        <part_log remove="1"/>
        <query_thread_log remove="1"/>
        <query_views_log remove="1"/>
        <session_log remove="1"/>
        <text_log remove="1"/>
        <processors_profile_log remove="1"/>
        <opentelemetry_span_log remove="1"/>
        <crash_log remove="1"/>
        <backup_log remove="1"/>
        <blob_storage_log remove="1"/>
        <s3_queue_log remove="1"/>
        <azure_queue_log remove="1"/>
        <zookeeper_log remove="1"/>
        <background_schedule_pool_log remove="1"/>

        <!-- Keep only query_log for debugging, with TTL -->
        <query_log>
          <database>system</database>
          <table>query_log</table>
          <flush_interval_milliseconds>7500</flush_interval_milliseconds>
          <ttl>event_date + INTERVAL 7 DAY DELETE</ttl>
        </query_log>
      '';
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