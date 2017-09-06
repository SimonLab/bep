defmodule Bep.UserController do
  use Bep.Web, :controller
  alias Bep.{User, Auth, Type}
  alias Ecto.Changeset

  def new(conn, _params) do
    types = Repo.all(Type)
    changeset = User.changeset(%User{})
    render conn, "new.html", changeset: changeset, types: types
  end

  def create(conn, %{"user" => user_params}) do
    types = Repo.all(Type)
    user_types = types
    |> Enum.filter(fn(t) ->
      user_params["#{t.id}"] == "true"
    end)
    changeset = User.registration_changeset(%User{}, user_params)
    changeset = Changeset.put_assoc(changeset, :types, user_types)
    case Repo.insert(changeset) do
      {:ok, user} ->
        conn
        |> Auth.login(user)
        |> put_flash(:info, "Welcome to BestEvidence!")
        |> redirect(to: page_path(conn, :index))
      {:error, %{errors: [email: {"has already been taken", []}]}} ->
        conn
        |> redirect(to: session_path(conn, :new))
      {:error, changeset} ->
        render(conn, "new.html", changeset: changeset, types: types)
    end
  end

  def update(conn, %{"types" => types_params}) do
    types = Repo.all(Type)
    user_types = types
    |> Enum.filter(fn(t) ->
      types_params["#{t.id}"] == "true"
    end)

    user = User
    |> Repo.get(conn.assigns.current_user.id)
    |> Repo.preload(:types)

    changeset = user
    |> Changeset.change()
    |> Changeset.put_assoc(:types, user_types)
    Repo.update!(changeset)
    redirect(conn, to: page_path(conn, :index))
  end

  def delete(conn, _) do
   conn
   |> Auth.logout()
   |> redirect(to: page_path(conn, :index))
 end

end
