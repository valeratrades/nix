{
  path = "/home/v/s/g/rolodex/people";
  tags = {
    ServiceArb = { type = "bool"; };
  };
  rank = [
    { of = "venue_activity"; decay = 3; weight = 1; }
  ];
}
