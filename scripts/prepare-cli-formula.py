#!/usr/bin/env python3
"""Generate a tap formula only from an existing verified stable CLI release.
Read-only network access; never publish, install, execute a downloaded binary or
promote a candidate. Tests inject synthetic responses, not placeholder releases.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import urllib.request
import zipfile

REPO = 'douyixuan/stickies'
API = f'https://api.github.com/repos/{REPO}'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'istk-release-preflight'})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(32 * 1024 * 1024 + 1)
    require(len(data) <= 32 * 1024 * 1024, 'Response exceeds release size limit')
    return data


def prepare(tag, read=fetch):
    require(re.fullmatch(r'cli-v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', tag),
            'Use an exact stable cli-vMAJOR.MINOR.PATCH tag')
    version = tag[5:]
    release = json.loads(read(f'{API}/releases/tags/{tag}'))
    require(release.get('tag_name') == tag and release.get('draft') is False
            and release.get('prerelease') is False and release.get('published_at'),
            'A published non-draft, non-prerelease release is required')
    commit = json.loads(read(f'{API}/commits/{tag}'))['sha']
    require(re.fullmatch(r'[0-9a-f]{40}', commit), 'Invalid tagged source SHA')
    assets = release.get('assets', [])

    def asset(name):
        matches = [a for a in assets if a.get('name') == name]
        require(len(matches) == 1, f'Missing or duplicate release asset: {name}')
        entry = matches[0]
        url = f'https://github.com/{REPO}/releases/download/{tag}/{name}'
        require(entry.get('state') == 'uploaded' and entry.get('browser_download_url') == url,
                'Asset must use the fixed release download URL')
        data = read(url)
        digest = 'sha256:' + hashlib.sha256(data).hexdigest()
        require(entry.get('digest') == digest, 'GitHub release asset digest mismatch')
        return data, url

    evidence, _ = asset('verification.json')
    report = json.loads(evidence)
    require(report.get('sourceSHA') == commit, 'Release tag and verified source differ')
    require(report.get('isolatedCLIRegression') == 'passed', 'CLI acceptance evidence missing')
    run_id = report.get('ciRunID')
    require(type(run_id) is int and run_id > 0, 'Exact CI run ID is required')
    run = json.loads(read(f'{API}/actions/runs/{run_id}'))
    require(run.get('head_sha') == commit and run.get('conclusion') == 'success'
            and run.get('status') == 'completed' and run.get('path') == '.github/workflows/build.yml',
            'Exact tagged source must have successful repository CI')
    archive_name = f'istk-{version}-macos-arm64.zip'
    archive, url = asset(archive_name)
    digest = hashlib.sha256(archive).hexdigest()
    verified = report.get('standaloneCLI', {})
    require(verified.get('archive') == archive_name and verified.get('sha256') == digest
            and verified.get('verification') == 'passed', 'Archive differs from verified CLI')
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        require(set(z.namelist()) == {'istk', 'manifest.json', 'USAGE.txt'}
                and len(z.infolist()) == 3, 'Unexpected or duplicate archive entries')
        require(all(i.file_size <= 32 * 1024 * 1024 for i in z.infolist()), 'Expanded asset too large')
        binary = z.read('istk')
        manifest = json.loads(z.read('manifest.json'))
        mode = z.getinfo('istk').external_attr >> 16
        require(mode & 0o170000 == 0o100000 and mode & 0o111, 'CLI must be an executable regular file')
    require(manifest.get('candidateOnly') is False and manifest.get('releaseVersion') == version,
            'Candidate archives cannot be promoted by this generator')
    require(manifest.get('sourceSHA') == commit and manifest.get('architectures') == ['arm64']
            and manifest.get('minimumMacOS') == '14.0' and manifest.get('schemaVersion') == 10,
            'Unsupported source, architecture, deployment target or schema')
    require(hashlib.sha256(binary).hexdigest() == manifest.get('binarySHA256')
            == verified.get('binarySHA256'), 'Executable hash mismatch')
    return f'''# Verified source: {commit}; CI run: {run_id}
class Istk < Formula
  desc "Command-line access to iStickies2 note profiles"
  homepage "https://github.com/{REPO}"
  url "{url}"
  version "{version}"
  sha256 "{digest}"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    bin.install "istk"
    pkgshare.install "manifest.json", "USAGE.txt"
  end

  def caveats
    <<~EOS
      Every data command requires --dir. Use a separate trial profile first.
      App-held profile locks allow reads and reject writes.
      First writes upgrade older profiles; back up the whole closed profile first.
      Rolling back the binary alone does not roll back the data format.
    EOS
  end

  test do
    profile = testpath/"isolated profile"
    system bin/"istk", "--dir", profile, "add", "Homebrew synthetic note"
    assert_match "Homebrew synthetic note", shell_output("#{{bin}}/istk --dir '#{{profile}}' list")
    assert_match "Homebrew synthetic note", shell_output("#{{bin}}/istk --dir '#{{profile}}' search synthetic")
  end
end
'''


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        formula = prepare(args.tag)
        # Exclusive creation: errors never overwrite an existing tap formula.
        with args.output.open('x') as out:
            out.write(formula)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f'Release preflight failed: {error}\n')
