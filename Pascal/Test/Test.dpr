program Test;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  MainUnit in 'MainUnit.pas',
  PureParseFloat in '..\PureParseFloat\PureParseFloat.pas';

begin
  RunTests();
end.
