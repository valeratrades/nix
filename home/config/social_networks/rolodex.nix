{
  path = "/home/v/s/g/rolodex/people";
  tags = {
    ServiceArb = { type = "bool"; };
    networth = { type = "number"; min = 0; max = 1; about = "estimated net worth: 0 is nothing to speak of, 0.5 comfortably well-off, 1 very wealthy"; };
    intelligence = { type = "number"; min = 0; max = 1; about = "how sharp they are, judged from how they reason and what they have built"; };
    willingness_to_share = { type = "number"; min = 0; max = 1; about = "how freely they share what they know, their contacts and their opportunities"; };
    social_capital = { type = "number"; min = 0; max = 1; about = "their reach and standing, who they know and who listens to them, relative to mine"; };
  };
  rank = [
    { of = "networth"; weight = 2; }
    { of = "intelligence"; weight = 2; }
    { of = "willingness_to_share"; weight = 2; }
    { of = "social_capital"; weight = 2; }
    { of = "venue_activity"; decay = 3; weight = 1; }
  ];
}
