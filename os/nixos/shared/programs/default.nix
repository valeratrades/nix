#TODO: figure out how to map the programs attrs defined in imports over to `programs` right here, instead of having to do `programs.xxx = ` in each of the imported files instead of simple `xxx = `
{ mylib, ... }:
{
  imports = mylib.scanPaths ./.;
}
