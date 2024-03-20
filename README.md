# Stanford Arclight Demo

## Starting the development server
```shell
bundle
yarn
./bin/dev
```

## Starting Solr for development
The following command will start a local Solr instance at `localhost:8983`, with a pre-loaded core named `blacklight-core`.

```shell
docker compose up
```

You can load fixture data locally: 
```shell
rake seed
```

This command will loop through all the directories under `spec/fixtures/ead`, for example `spec/fixtures/ead/ars` and `spec/fixtures/ead/uarc`, and index all the .xml files present. The names of these subdirectories must correspond with a top-level key in the `repositories.yml` file. For example, `uarc` is a top-level key in `respositories.yml`, as well as the title of a subdirectory under `spec/fixtures/ead`. A mis-match will cause indexing issues.


#### Managing data
Data for the solr and redis services are persisted using docker named volumes. You can see what volumes are currently present with:

```shell
docker volume ls
````

If you want to remove a volume (e.g. to start with a fresh database or solr core), you can run:

```shell
docker volume rm stanford-arclight_solr-data   # to remove the solr data
```

## Using Sidekiq for development
There are multiple options for working with data in development. In some cases you might want to index a large number of collections from ArchivesSpace and utilize the `DownloadEadJob` and `IndexEadJob`. By default in development Rails will run these jobs with the `:async` adapter. If you prefer to run these jobs in the background you can use Sidekiq.

### Steps to enable Sidekiq
1. In `config/environments/development.rb`, add the line: `config.active_job.queue_adapter = :sidekiq`
2. Make sure Redis and Solr are running. The included Docker enviroment will start both Redis and Solr for you.
3. Start Sidekiq:
```shell
bundle exec sidekiq
```
4. Run a job. For example, to download and index all the `ars` (Archive of Recorded Sound) collections updated after March 1, 2024, run:
```shell
bin/rails runner 'DownloadEadJob.enqueue_one_by(aspace_repository_code: "ars", updated_after: "2024-03-01")'
```
5. You can monitor job progress in the Sidekiq admin UI, which is available at: `http://localhost:3000/sidekiq`