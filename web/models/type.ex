defmodule Bep.Type do
  @moduledoc """
  Type model
  """
  use Bep.Web, :model
  alias Bep.{User}

  schema "types" do
    field :type, :string
        many_to_many :users, User, join_through: UserType, on_replace: :delete
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:type])
    |> validate_required([:type])
  end
end
