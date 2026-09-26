# Leads to ask for a review. The weights are a starting point to tune; the `near` location is a placeholder.
{
  path = "/home/v/s/g/rolodex/reviews";
  tags = {
    business = { type = "bool"; about = "runs a business of their own"; };
    last_login = { type = "timestamp"; };
    interest = { type = "number"; min = 0; max = 1; about = "degree of interest shown"; };
    age = { type = "range"; };
    lives_in = { type = "place"; };
  };
  rank = [
    { of = "business"; weight = 7; }
    { of = "interactions"; weight = 6; }
    { of = "last_interaction"; decay = 3; weight = 5; }
    { of = "last_login"; decay = 3; weight = 4; }
    { of = "interest"; weight = 3; }
    { of = "age"; within = [ 25 55 ]; weight = 2; }
    # the business location
    { of = "lives_in"; near = { lat = 48.8566; lon = 2.3522; radius_km = 30; halving_km = 50; }; weight = 1; }
  ];
}
