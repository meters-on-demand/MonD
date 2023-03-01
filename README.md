# Meters on Demand

Rainmeter package manager

# Usage

Update the list of available skins

```
mond update
```

Install a skin

```
mond install owner/name
```

eg. `mond install reisir/robux`

# Development

Information for developers

## Scraping rainmeter-skins topic to skins.json

Make a new script called `.env.ps1` in #ROOTCONFIGPATH# and put your GitHub [Personal Access Token](https://github.com/settings/tokens) in there like this:

```ps1
$TOKEN = ConvertTo-SecureString -String "ghp_yourTokenGoesHere" -AsPlainText -Force
```

If you do not set `$TOKEN`, MonD will assume you're a normal user and update the skins.json from reisir/MonD without scraping GitHub.

This is because GitHubs API has a rate limit of like 10 requests per minute if you're not authenticated. The scraping process does one request per repository found in the [rainmeter-skin](https://github.com/topics/rainmeter-skin) topic.

# TODO

- autoupdate self / skins.json when available
- api skin authors can ping / use a github webhook to automatically ping whenever they release a new version

# Credits

- JSON formatter by @stedolan https://github.com/stedolan/jq/
