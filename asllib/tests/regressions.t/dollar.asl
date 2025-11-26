func foo$bar() => integer
begin
  return 0;
end;

func main() => integer
begin
  return foo$bar();
end;
