# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Bep.Repo.insert!(%Bep.SomeModel{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
alias Bep.{Repo, Type}
types = Type.get_list

for type <- types do
  Repo.insert!(%Type{type: type})
end
