{opts, _, _} = OptionParser.parse(System.argv(), strict: [in: :string, out: :string])
source = File.read!(opts[:in])
dest = Keyword.fetch!(opts, :out)

IO.puts("Preprocessing #{opts[:in]} and writing to #{dest}")

migration =
  Regex.scan(~r/^CREATE OR REPLACE FUNCTION ([a-z_]+\()/m, source)
  |> Enum.map(fn [_, f] -> f end)
  |> Enum.uniq()
  |> Enum.reduce(source, fn func, source ->
    String.replace(
      source,
      func,
      "@schemaname@.#{func}",
      global: true
    )
  end)

File.write!(dest, migration, [])
