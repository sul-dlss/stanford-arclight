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
### Managing data
Data for the solr and redis services are persisted using docker named volumes. You can see what volumes are currently present with:

```shell
docker volume ls
````

If you want to remove a volume (e.g. to start with a fresh database or solr core), you can run:

```shell
docker volume rm stanford-arclight_solr-data   # to remove the solr data
```

## Working with data in development

### Fixture data (also used by the test suite)

You can load fixture data locally: 
```shell
rake seed
```

This command will loop through all the directories under `spec/fixtures/ead`, for example `spec/fixtures/ead/ars` and `spec/fixtures/ead/uarc`, and index all the .xml files present. The names of these subdirectories must correspond with a top-level key in the `repositories.yml` file. For example, `uarc` is a top-level key in `repositories.yml`, as well as the title of a subdirectory under `spec/fixtures/ead`. A mis-match will cause indexing issues.

### Loading more data

The easiest way to load data other than the fixtures is to use the `DownloadEadJob` and/or the `IndexEadJob`. See below for instructions about how to use Sidekiq to run these jobs in development. Under most circumstances it's fine to use the default `:async` adapter to run these jobs without Sidekiq in development. 

By default the `DownloadEadJob` will store EAD files in the directory set in `./config/settings.yml` as `Settings.data_dir`. You can choose a different location by setting the `DATA_DIR` environment variable, passing `data_dir:` argument to the job method, or by setting a different location for `data_dir` in `./config/settings.local.yml`

The `DownloadEadJob` will attempt to use the ASpace API to download EADs. You will need to configure the API URL with username and password in order to connect to ASpace. To do this you will need to add the following to `config/settings.local.yml` with the correct URL, port, and account information:

```
aspace:
  default:
    user: USERNAME
    password: PASSWORD
    url: "http://ARCHIVESPACE_URL:PORT"
  chs:
    user: USERNAME
    password: PASSWORD
    url: "http://ARCHIVESPACE_URL:PORT"
```

_**Important Note:**_ ArcLight core includes a number of rake tasks for loading data into Solr, such `rake arclight:index`, `rake arclight:index_dir`, `rake arclight:index_url`, and `rake arclight:index_url_batch`. Using these rake tasks will use the default Traject indexing rules from ArcLight core only and WILL NOT apply any of the local Traject indexing rules. It's important to use either the local app's `IndexEadJob` or the Traject command (`REPOSITORY_ID={REPO_ID} bundle exec traject -u {SOLR_URL} -i xml -c ./lib/traject/sul_config.rb {FILE_PATH}`) to index data that will work correctly with stanford-arclight.

#### Using Sidekiq for development
By default in development Rails will run the `DownloadEadJob` and `IndexEadJob` jobs with the `:async` adapter. If you prefer to run these jobs in the background you can use Sidekiq.

##### Steps to enable Sidekiq
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

### Deleting a collection
There is a rake task for deleting a single collection and all of its components from the Solr index.

1. Find the Solr document id for the collection (which is a form of the EAD ID)
2. Run the rake task:
```shell
# Some shells (such as zsh) require that the brackets are escaped.
bundle exec rake stanford_arclight:delete_by_id\['ars0167'\]
```
3. Enter YES at the prompt to delete the collection and its components.

### Efficient bulk re-indexing
During normal operations we don't expect large numbers of finding aids to change each day. For simplicity we enqueue one indexing job per file. However, if you need to re-index an entire repository or the whole corpus it's much more efficient to send multiple files to an indexing job. If you don't need to re-download the EAD files you can proceed by running the rake task described below, which will add up to 100 EADs to each indexing job. If you do need to re-download all the EAD files from ArchivesSpace you should do that first and wait for all the jobs to finish before proceeding (To re-download everything you would run: `bin/rails runner 'DownloadEadJob.enqueue_all(config: DownloadEadJob::Config.new(index: false, generate_pdf: false))'`), then proceed as follows:

To re-index all downloaded EAD files in all repositories:
```shell
bundle exec rake stanford_arclight:reindex_all
```

To re-index all downloaded EAD files in a single repository pass the Arclight Repository code/slug as an argument to the job:
```shell
# Some shells (such as zsh) require that the brackets are escaped.
bundle exec rake stanford_arclight:reindex_all\['uarc'\]
```

## PDF Generation
### Requirements
Finding aid PDFs can be automatically generated from EAD XML. The following are needed:
- [Saxon](https://www.saxonica.com/welcome/welcome.xml)
- [Apache FOP](https://xmlgraphics.apache.org/fop/)
- Java

### Configuration
Paths to those tools must be configured in `./config/settings.yml`.
- `Settings.pdf_generation.fop_path` to specify the path to the fop executable
- `Settings.pdf_generation.saxon_path` to specify the path to the saxon jar

The path to the referenced fonts must be set in `config/pdf_generation/fop-config.xml`. They are not bundled in this repository. They can be found in [ArchivesSpace](https://github.com/archivesspace/archivesspace).

PDFs can be automatically generated as part of `DownloadEadJob` by setting `Settings.pdf_generation.create_on_ead_download`.

### Running a PDF Generation Job
The `GeneratePdfJob` can be used to generate PDFs not created automatically via `DownloadEadJob`.

For example, the following generates all missing PDFs but does not regenerate existing PDFs:
```shell
bin/rails runner 'GeneratePdfJob.enqueue_all'
```
