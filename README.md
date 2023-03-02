# Meters on Demand

![MonD splash](https://repository-images.githubusercontent.com/601636170/25834e41-d86e-4f2a-809c-441ab80c2a8a)

Rainmeter package manager. Install skins directly from Rainmeter!

## Installation

Download the latest .rmskin from [releases](https://github.com/reisir/mond/releases/latest) and install it. 

## Usage 

Once you've installed the skin, it should open automatically. You can use the arrows to switch pages and the top to search. Each skin has buttons to open the GitHub repo for more information or to install / update / uninstall.

# Commandline Usage

FOR ADVANCED USERS!!!

I've yet to make a way to actually call mond without having to use `.\mond.ps1` so these are more like future plans than current documentation.

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

eg. `mond install reisir/robux`

Upgrade a skin

```
mond upgrade owner/name
```

Uninstall a skin

```
mond uninstall owner/name
```

# Development

Information for developers

## Adding your skin to MonD

Make a GitHub repository for your skin. Add a release with an .rmskin package included and ask for the main repository to be updated. You may also run `.\mond.ps1 update your/skin` yourself and make a pull request.

## Scraping rainmeter-skins topic to skins.json

Make a new script called `.env.ps1` in #ROOTCONFIGPATH# and put a GitHub [Personal Access Token](https://github.com/settings/tokens) in there like this:

```ps1
$TOKEN = ConvertTo-SecureString -String "ghp_yourTokenGoesHere" -AsPlainText -Force
```

This is because GitHubs API has a rate limit of like 10 requests per minute if you're not authenticated. The scraping process does one request per repository found in the [rainmeter-skin](https://github.com/topics/rainmeter-skin) topic.

To scrape GitHub, use `.\mond.ps1 update -Scrape`

# TODO

- deactivate all active configs before uninstalling
- api skin authors can ping / use a github webhook to automatically ping whenever they release a new version

# Credits

- Installer header and GitHub splash background image by [MA SH](https://www.artstation.com/artwork/L36yml)
