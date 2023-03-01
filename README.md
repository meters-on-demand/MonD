# Meters on Demand

Rainmeter package manager

# Usage

Update the list of available skins

```
mond update
```

Search the skin list

```
mond search
```

Install a skin

```
mond install owner/name
```

Upgrade a skin

```
mond upgrade owner/name
```

Uninstall a skin

```
mond uninstall owner/name
```

eg. `mond install reisir/robux`

# Development

Information for developers

## Scraping rainmeter-skins topic to skins.json

Make a new script called `.env.ps1` in #ROOTCONFIGPATH# and put your GitHub [Personal Access Token](https://github.com/settings/tokens) in there like this:

```ps1
$TOKEN = ConvertTo-SecureString -String "ghp_yourTokenGoesHere" -AsPlainText -Force
```

This is because GitHubs API has a rate limit of like 10 requests per minute if you're not authenticated. The scraping process does one request per repository found in the [rainmeter-skin](https://github.com/topics/rainmeter-skin) topic.

To scrape GitHub, use `mond update -Scrape`

# TODO

- deactivate all active configs before uninstalling
- api skin authors can ping / use a github webhook to automatically ping whenever they release a new version

# Credits

- Installed header background image by [MA SH](https://www.artstation.com/artwork/L36yml)
