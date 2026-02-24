# frozen_string_literal: true

# Custom download strategy for private GitHub repository release assets.
# Requires HOMEBREW_GITHUB_API_TOKEN to be set.
#
# Based on the former GitHubPrivateRepositoryReleaseDownloadStrategy
# that was removed from Homebrew core in v2.
#
# Usage in formula:
#   require_relative "../lib/private_strategy"
#   url "https://github.com/OWNER/REPO/releases/download/vVERSION/FILE.tar.gz",
#       using: GitHubPrivateRepositoryReleaseDownloadStrategy

require "download_strategy"

class GitHubPrivateRepositoryDownloadStrategy < CurlDownloadStrategy
  def initialize(url, name, version, **meta)
    super
    parse_url_pattern
    set_github_token
  end

  private

  def parse_url_pattern
    url_pattern = %r{https://github\.com/([^/]+)/([^/]+)/releases/download/([^/]+)/(.+)}
    unless @url =~ url_pattern
      raise CurlDownloadStrategyError, "Invalid GitHub release URL pattern: #{@url}"
    end

    @owner = Regexp.last_match(1)
    @repo = Regexp.last_match(2)
    @tag = Regexp.last_match(3)
    @filename = Regexp.last_match(4)
  end

  def set_github_token
    @github_token = ENV.fetch("HOMEBREW_GITHUB_API_TOKEN", nil)
    unless @github_token
      raise CurlDownloadStrategyError,
            "HOMEBREW_GITHUB_API_TOKEN is required to install from a private repository. " \
            "Set it with: export HOMEBREW_GITHUB_API_TOKEN=ghp_your_token"
    end
  end
end

class GitHubPrivateRepositoryReleaseDownloadStrategy < GitHubPrivateRepositoryDownloadStrategy
  def initialize(url, name, version, **meta)
    super
  end

  def fetch(timeout: nil, **_options)
    asset_id = resolve_asset_id
    download_from_api(asset_id, timeout: timeout)
  end

  private

  def resolve_asset_id
    release_url = "https://api.github.com/repos/#{@owner}/#{@repo}/releases/tags/#{@tag}"
    response = GitHub::API.open_rest(release_url)
    assets = response["assets"]

    asset = assets.find { |a| a["name"] == @filename }
    raise CurlDownloadStrategyError, "Asset #{@filename} not found in release #{@tag}" unless asset

    asset["id"]
  end

  def download_from_api(asset_id, timeout: nil)
    asset_url = "https://api.github.com/repos/#{@owner}/#{@repo}/releases/assets/#{asset_id}"
    ohai "Downloading #{@filename} from private release #{@tag}"

    # Use curl with the appropriate headers for binary download
    curl_args = [
      "--header", "Authorization: token #{@github_token}",
      "--header", "Accept: application/octet-stream",
      "--location",
      "--output", temporary_path.to_s,
      asset_url,
    ]
    curl_args.prepend("--max-time", timeout.to_s) if timeout

    curl(*curl_args, secrets: [@github_token])
    ignore_interrupts { temporary_path.rename(cached_location) }
  rescue ErrorDuringExecution
    raise CurlDownloadStrategyError, "Failed to download #{@filename} from private release"
  end
end
