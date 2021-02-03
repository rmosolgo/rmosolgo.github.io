---
layout: post
title: "Convert country names and codes with Countrysaurus"
date: 2013-10-07 21:56
categories:
  - International Relations
  - Data Management
  - Ruby
  - Sinatra
---

[Countrysaurus](http://countrysaurus.herokuapp.com/) is an online tool for merging country codes into a CSV spreadsheet with country names in it. You can also download a CSV of country codes or access it via [REST API](http://countrysaurus.herokuapp.com/api_documentation).

<!-- more -->


In my old job, I often had spreadsheets with (sometimes misspelled) country names, but I needed to feed data into something with country codes, be it ISO-2, ISO-3, OECD, AidData, whatever kind of code.

Finally, I hammered out a little web app with Ruby's [Sinatra](http://www.sinatrarb.com/) web framework to help with this problem. You can upload a (small- or medium-sized) CSV spreadsheet and it will:

- Identify unique country names
- Allow you to pick which kinds of codes you need
- Suggest matches
- Allow you to add new matches (in case it doesn't have your country name already)
- Allow you to download your spreadsheet.

It's also [on Github](https://github.com/rmosolgo/country-fixer). [Try it out!](http://countrysaurus.herokuapp.com/)
