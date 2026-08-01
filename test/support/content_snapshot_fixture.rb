module ContentSnapshotFixture
  def create_product_tree(root, s01_status: "published", s02_status: "published")
    root.mkpath
    root.join("catalog.yml").write({
      "schema_version" => 1,
      "product" => { "code" => "chatdox", "title" => "CHATDOX" },
      "seasons" => [
        { "code" => "s01", "order" => 1, "path" => "s01" },
        { "code" => "s02", "order" => 2, "path" => "s02" }
      ]
    }.to_yaml)
    create_season(root, "s01", 1, s01_status)
    create_season(root, "s02", 2, s02_status)
  end

  def create_season(root, code, order, published_status)
    season = root.join(code)
    season.join("images/nested").mkpath
    prefix = code.upcase
    episodes = [
      episode(prefix, 1, published_status, "#{prefix}E01_first"),
      episode(prefix, 2, "draft", "#{prefix}E02_draft")
    ]
    season.join("content_meta.yml").write({
      "schema_version" => 1,
      "season" => {
        "code" => code,
        "order" => order,
        "title" => "Season #{order}",
        "status" => order == 1 ? "completed" : "upcoming",
        "guest_episode_limit" => order == 1 ? 2 : 1,
        "trial_episode_limit" => order == 1 ? 5 : 2,
        "images_dir" => "images"
      },
      "phases" => [ {
        "key" => "foundation",
        "order" => 1,
        "title" => "Foundation",
        "episode_ids" => episodes.pluck("id")
      } ],
      "episodes" => episodes
    }.to_yaml)
    season.join("#{prefix}E01_first.md").write(<<~MARKDOWN)
      # Published

      ![Used](/docs/images/used.png)

      ```markdown
      ![Example only](/docs/images/example-only.png)
      ```

      ![Nested](images/nested/diagram.png)
    MARKDOWN
    season.join("#{prefix}E02_draft.md").write("# Draft\n")
    season.join("images/used.png").binwrite("\x89PNG\r\nfixture".b)
    season.join("images/nested/diagram.png").binwrite("\x89PNG\nNested".b)
    season.join("images/example-only.png").binwrite("not public".b)
  end

  def episode(prefix, number, status, slug)
    {
      "id" => format("%sE%02d", prefix, number),
      "number" => number,
      "order" => number,
      "slug" => slug,
      "title" => "Episode #{number}",
      "status" => status,
      "phase" => "foundation"
    }
  end

  def init_git_repository(repository, content_root: "hq/chatdox")
    repository.mkpath
    run_git(repository, "init", "-q")
    run_git(repository, "config", "user.email", "snapshot@example.com")
    run_git(repository, "config", "user.name", "Snapshot Test")
    repository.join(".gitignore").write(".local/\n")
    create_product_tree(repository.join(content_root))
    run_git(repository, "add", ".")
    run_git(repository, "commit", "-qm", "content baseline")
  end

  def run_git(repository, *arguments)
    system("git", "-C", repository.to_s, *arguments, exception: true)
  end
end
