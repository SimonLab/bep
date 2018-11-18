defmodule Bep.BearController do
  use Bep.Web, :controller
  alias Bep.{
    BearAnswers, BearQuestion, BearStat, BearView, NoteSearch, PicoOutcome,
    PicoSearch, Publication, Search, User
  }
  alias Phoenix.View
  alias Ecto.Changeset

  @in_light "In light of the above assessment,"
  @further "Any further comments?"

  def create_pdf(conn, %{"publication_id" => pub_id, "pico_search_id" => ps_id}) do
    render(conn, "create_pdf.html", pub_id: pub_id, pico_search_id: ps_id)
  end

  def download_pdf(conn, %{"publication_id" => pub_id, "pico_search_id" => ps_id,
    "user_name" => user_name, "short_title" => short_title, "org_name" => org_name,
    "dec_title" => dec_title, "question" => question}) do

    # pico search details
    pico_outcomes =
      ps_id
      |> PicoOutcome.get_pico_outcomes()
      |> PicoOutcome.unique_outcomes()

    pico_search =
      PicoSearch
      |> Repo.get(ps_id)
      |> Map.put(:pico_outcomes, pico_outcomes)

    note_search = Repo.get!(NoteSearch, pico_search.note_search_id)
    search = Repo.get!(Search, note_search.search_id)

    # paper details
    publication = Repo.get!(Publication, pub_id)

    paper_details_questions =
      BearQuestion.all_questions_for_sec(pub_id, "paper_details")

    # check validity details
    check_validity_questions =
      BearQuestion.all_questions_for_sec(pub_id, "check_validity")

    in_light = Enum.find(check_validity_questions, &(&1.question =~ @in_light))

    in_light_outcome_answers =
      get_outcome_answers_for_question(pico_outcomes, in_light, pub_id)

    check_validity = %{
      first_six: Enum.take(check_validity_questions, 6),
      further: Enum.find(check_validity_questions, &(&1.question =~ @further)),
      in_light_outcome_answers: in_light_outcome_answers
    }

    # calculate results details
    calculate_results_questions =
      BearQuestion.all_questions_for_sec(pub_id, "calculate_results")

    note_question =
      Enum.find(calculate_results_questions, &(&1.question =~ "Notes"))

    yes_no_questions = Enum.take(calculate_results_questions, 4)
    [inter_yes, inter_no, control_yes, control_no] = yes_no_questions

    query_map =
      create_query_map(control_yes, control_no, inter_yes, inter_no, pub_id)

    pico_answers_queries =
      Enum.map(
        pico_outcomes,
        &create_query_for_calculate_res_yes_no_ans(&1, query_map)
      )

    yes_no_outcome_answers =
      case pico_outcomes do
        [] ->
          []
        _ ->
          1..length(pico_outcomes)
          |> Enum.map(fn(index) ->
            pico_answers_queries
            |> Enum.at(index - 1)
            |> Repo.all()
            |> Enum.sort(&(&1.bear_question_id < &2.bear_question_id))
            |> set_answers(Enum.at(pico_outcomes, index - 1))
          end)
      end

    bear_stats =
      pub_id
      |> BearStat.get_related_bear_stats(ps_id)
      |> Enum.take(length(yes_no_outcome_answers))

    yes_no_answers_with_stats = Enum.zip(yes_no_outcome_answers, bear_stats)

    calculate_results = %{
      yes_no_answers_with_stats: yes_no_answers_with_stats,
      note_question: note_question
    }

    # relevance details
    relevance_questions =
      BearQuestion.all_questions_for_sec(pub_id, "relevance")

    relevance = %{
      expiry_date_question: Enum.at(relevance_questions, -1),
      first_three: Enum.take(relevance_questions, 3),
      bottom_line: Enum.find(relevance_questions, &(&1.question =~ "bottom line"))
    }

    assigns = [
      user_name: user_name,
      short_title: short_title,
      org_name: org_name,
      dec_title: dec_title,
      note_search: note_search,
      question: question,
      pico_search: pico_search,
      search: search,
      publication: publication,
      paper_details_questions: paper_details_questions,
      check_validity: check_validity,
      calculate_results: calculate_results,
      relevance: relevance
    ]

    pdf_content =
      BearView
      |> View.render_to_string("pdf.html", assigns)
      |> PdfGenerator.generate_binary!()

    conn
    |> put_resp_content_type("application/pdf")
    |> put_resp_header("content-disposition", "attachment; filename=BEAR.pdf")
    |> send_resp(200, pdf_content)
  end

  def index(conn, _) do
    user = conn.assigns.current_user
    searches =
      User.get_all_notes(user).searches
      |> Search.group_searches_by_day()
      |> Enum.filter(fn({_date, searches}) ->
        Enum.any?(searches, &has_publications?/1)
      end)
      |> Enum.map(fn({date, searches}) ->
        filtered_searches =
          searches
          |> Enum.filter(&has_publications?/1)
          |> add_pico_search_id_to_searches()

        {date, filtered_searches}
      end)

    render(conn, "index.html", searches: searches)
  end

  def complete(conn, %{"publication_id" => pub_id, "pico_search_id" => ps_id}) do
    render(conn, :complete, pub_id: pub_id, ps_id: ps_id)
  end

  def paper_details(conn, %{"publication_id" => pub_id, "pico_search_id" => ps_id}) do
    changeset = BearAnswers.changeset(%BearAnswers{})
    questions = BearQuestion.all_questions_for_sec(pub_id, ps_id, "paper_details")
    publication = Repo.get!(Publication, pub_id)

    assigns = [
      changeset: changeset,
      publication: publication,
      questions: questions,
      pico_search_id: ps_id
    ]

    render(conn, :paper_details, assigns)
  end

  def check_validity(conn, %{"pico_search_id" => ps_id, "publication_id" => pub_id}) do
    changeset = BearAnswers.changeset(%BearAnswers{})
    all_questions = BearQuestion.all_questions_for_sec(pub_id, ps_id, "check_validity")
    in_light_question = Enum.find(all_questions, &(&1.question =~ @in_light))

    outcomes =
      ps_id
      |> PicoSearch.get_related_pico_outcomes(9)
      |> get_outcome_answers_for_question(in_light_question, pub_id)

    further_question = Enum.find(all_questions, &(&1.question =~ @further))
    questions =
      all_questions
      |> Enum.reject(&(&1.question =~ @in_light))
      |> Enum.reject(&(&1.question =~ @further))

    question_nums = 1..length(questions)

    assigns = [
      changeset: changeset,
      questions: Enum.zip(question_nums, questions),
      in_light: in_light_question,
      further: further_question,
      pub_id: pub_id,
      pico_search_id: ps_id,
      outcomes: outcomes
    ]

    render(conn, :check_validity, assigns)
  end

  def calculate_results(conn,  %{"pico_search_id" => ps_id, "publication_id" => pub_id}) do
    changeset = BearAnswers.changeset(%BearAnswers{})
    questions = BearQuestion.all_questions_for_sec(pub_id, ps_id, "calculate_results")
    yes_no_questions = Enum.take(questions, 4)
    [inter_yes, inter_no, control_yes, control_no] = yes_no_questions
    note_question = Enum.find(questions, &(&1.question =~ "Notes"))

    pico_outcomes = PicoSearch.get_related_pico_outcomes(ps_id, 9)
    query_map =
      create_query_map(control_yes, control_no, inter_yes, inter_no, pub_id)

    pico_answers_queries =
      Enum.map(
        pico_outcomes,
        &create_query_for_calculate_res_yes_no_ans(&1, query_map)
      )

    updated_outcomes =
      case pico_outcomes do
        [] ->
          []
        _ ->
          1..length(pico_outcomes)
          |> Enum.map(fn(index) ->
            pico_outcome = set_questions(pico_outcomes, index, yes_no_questions)

            pico_answers_queries
            |> Enum.at(index - 1)
            |> Repo.all()
            |> Enum.sort(&(&1.bear_question_id < &2.bear_question_id))
            |> set_answers(pico_outcome)
          end)
      end

    assigns = [
      changeset: changeset,
      pub_id: pub_id,
      pico_search_id: ps_id,
      note_question: note_question,
      updated_outcomes: updated_outcomes
    ]

    render(conn, :calculate_results, assigns)
  end

  def relevance(conn, %{"pico_search_id" => ps_id, "publication_id" => pub_id}) do
    changeset = BearAnswers.changeset(%BearAnswers{})

    [inter_yes, inter_no, control_yes, control_no] =
      pub_id
      |> BearQuestion.all_questions_for_sec(ps_id, "calculate_results")
      |> Enum.take(4)

    query_map =
      create_query_map(control_yes, control_no, inter_yes, inter_no, pub_id)

    pico_outcomes = PicoSearch.get_related_pico_outcomes(ps_id, 1)

    outcome_answers =
      case pico_outcomes do
        [] ->
          ""
        [pico_outcome] ->
          pico_outcome
          |> create_query_for_calculate_res_yes_no_ans(query_map)
          |> Repo.all()
          |> Enum.sort(&(&1.bear_question_id < &2.bear_question_id))
          |> Enum.map(&Map.get(&1, :answer))
          |> Enum.join(",")
      end

    question_nums = 1..3
    all_questions = BearQuestion.all_questions_for_sec(pub_id, ps_id, "relevance")

    {first_three, rest} = Enum.split(all_questions, 3)
    {[prob, comment], dates} = Enum.split(rest, 2)

    assigns = [
      changeset: changeset,
      outcome_answers: outcome_answers,
      pub_id: pub_id,
      pico_search_id: ps_id,
      first_three: Enum.zip(question_nums, first_three),
      prob: prob,
      comment: comment,
      dates: dates
    ]

    render(conn, :relevance, assigns)
  end

  # create bear_answers
  def create(conn, %{"next" => "relevance", "bear_answers" => bear_answers}) do
    %{"pub_id" => pub_id, "pico_search_id" => ps_id} = bear_answers
    pub = Repo.get(Publication, pub_id)
    ps = Repo.get(PicoSearch, ps_id)
    bear_stats = BearStat.get_related_bear_stats(pub_id, ps_id)

    case bear_stats do
      [] ->
        Enum.each(1..9, fn(index) ->
          stat = create_bear_stat_map(bear_answers, index)

          %BearStat{}
          |> BearStat.changeset(stat)
          |> Changeset.put_assoc(:publication, pub)
          |> Changeset.put_assoc(:pico_search, ps)
          |> Repo.insert!()
        end)
      _ ->
        Enum.each(bear_stats, fn(bear_stat) ->
          stat = create_bear_stat_map(bear_answers, bear_stat.index)

          bear_stat
          |> BearStat.changeset(stat)
          |> Repo.update!()
        end)
    end

    insert_bear_answers(bear_answers, pub, ps)
    redirect_path = get_path(conn, "relevance", pub_id, ps_id)
    redirect(conn, to: redirect_path)
  end

  def create(conn, %{"next" => page, "bear_answers" => bear_answers}) do
    %{"pub_id" => pub_id, "pico_search_id" => ps_id} = bear_answers
    pub = Repo.get(Publication, pub_id)
    ps = Repo.get(PicoSearch, ps_id)

    insert_bear_answers(bear_answers, pub, ps)
    redirect_path = get_path(conn, page, pub_id, ps_id)
    redirect(conn, to: redirect_path)
  end

  # save and continue later route for bear_form
  def create(conn, %{"pub_id" => pub_id, "pico_search_id" => ps_id} = params) do
    pub = Repo.get(Publication, pub_id)
    ps = Repo.get(PicoSearch, ps_id)

    insert_bear_answers(params, pub, ps)
    redirect(conn, to: search_path(conn, :index))
  end

  # HELPERS
  def get_outcome_answers_for_question(outcomes, question, pub_id) do
    outcomes
    |> Enum.map(fn(po) ->
      query =
        from ba in BearAnswers,
        where: ba.bear_question_id == ^question.id
        and ba.publication_id == ^pub_id
        and ba.index == ^po.o_index,
        order_by: [desc: ba.id],
        limit: 1

      bear_ans = Repo.one(query)
      case bear_ans do
        nil ->
          Map.put(po, :answer, "")
        _ ->
          Map.put(po, :answer, bear_ans.answer)
      end
    end)
  end

  def get_path(conn, page, pub_id, ps_id) do
    assigns = [publication_id: pub_id, pico_search_id: ps_id]
    case page do
      "check_validity" ->
        bear_path(conn, :check_validity, assigns)

      "calculate_results" ->
        bear_path(conn, :calculate_results, assigns)

      "relevance" ->
        bear_path(conn, :relevance, assigns)

      "complete_bear" ->
        bear_path(conn, :complete, assigns)
    end
  end

  def insert_bear_answers(params, pub, ps) do
    params
    |> make_q_and_a_list()
    |> Enum.map(&BearAnswers.insert_ans(%BearAnswers{}, &1, pub, ps))
  end

  def make_q_and_a_list(params) do
    params
    |> Map.keys()
    |> Enum.filter(&(&1 =~ "q_"))
    |> Enum.map(fn(key) ->

      {bear_q_id, o_index} = get_bear_q_id_and_o_index(key)
      answer = params |> Map.get(key) |> date_to_str()

      if answer != "", do: {answer, bear_q_id, o_index}

    end)
  end

  def date_to_str(answer) do
    if is_map(answer) do
      "#{answer["day"]}/#{answer["month"]}/#{answer["year"]}"
    else
      answer
    end
  end

  def get_bear_q_id_and_o_index(key) do
    str = key |> String.trim_leading("q_")

    case String.contains?(str, "o_index") do
      true ->
        [bear_q_id, _, _, o_index] = String.split(str, "_")
        {bear_q_id, o_index}
      false ->
        {str, nil}
    end
  end

  defp has_publications?(search) do
    search.publications !== [] && search.uncertainty == true
  end

  defp add_pico_search_id_to_searches(searches) do
    Enum.reduce(searches, [], fn(search, acc) ->
      note_search = search.note_searches
      pico_search = Repo.get_by(PicoSearch, note_search_id: note_search.id)

      case pico_search == nil do
        true ->
          [acc]
        false ->
          updated_ns = Map.put(note_search, :pico_search_id, pico_search.id)
          updated_search = Map.put(search, :note_searches, updated_ns)

          [updated_search, acc]
          |> Enum.reverse()
          |> List.flatten()
      end
    end)
  end

  def create_query_map(c_yes, c_no, i_yes, i_no, pub_id) do
    %{
      control_yes: c_yes,
      control_no: c_no,
      inter_yes: i_yes,
      inter_no: i_no,
      pub_id: pub_id,
    }
  end

  def create_query_for_calculate_res_yes_no_ans(pico_outcome, q_map) do
    from ba in BearAnswers,
    where: (ba.bear_question_id == ^q_map.control_yes.id
    or ba.bear_question_id == ^q_map.control_no.id
    or ba.bear_question_id == ^q_map.inter_yes.id
    or ba.bear_question_id == ^q_map.inter_no.id)
    and ba.publication_id == ^q_map.pub_id
    and ba.index == ^pico_outcome.o_index,
    order_by: [desc: ba.id],
    limit: 4
  end

  defp set_questions(outcomes, i, y_n_questions) do
    [inter_yes, inter_no, control_yes, control_no] = y_n_questions

    outcomes
    |> Enum.at(i - 1)
    |> Map.put(:questions, [
      inter_yes.id, inter_no.id, control_yes.id, control_no.id
    ])
  end

  defp set_answers(list, map) do
    case list do
      [ans1, ans2, ans3, ans4] ->
        Map.put(
          map,
          :answers,
          [ans1.answer, ans2.answer, ans3.answer, ans4.answer]
        )
      _ ->
        Map.put(map, :answers, ["", "", "", ""])
    end
  end

  defp create_bear_stat_map(bear_answers, index) do
    bear_answers
    |> Enum.reduce(%{}, fn({key, value}, acc) ->
      case String.contains?(key, "_input_#{index}") do
        true ->
          [key, _index] = String.split(key, "_input_")
          Map.put(acc, key, value)
        false -> acc
      end
    end)
    |> Map.put("index", index)
  end
end
