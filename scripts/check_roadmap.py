"""Offline product-tree and evidence gate. Does not execute linked commands."""
import argparse
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit

SHA = re.compile(r'^[0-9a-f]{40}$')


def slug(value):
    return re.sub(r'[^\w\-\s]', '', value.lower()).replace(' ', '-')


def local_link(root, source, reference):
    if not isinstance(reference, str) or not reference.strip():
        raise ValueError('Missing evidence or source link')
    parsed = urlsplit(reference)
    if parsed.scheme:
        if parsed.scheme != 'https' or not parsed.netloc:
            raise ValueError('Use repository links or HTTPS evidence')
        return  # Offline presence check only; external content is not authenticated.
    path = (source.parent / unquote(parsed.path)).resolve() if parsed.path else source
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f'Broken or outside-repository link: {reference}')
    if parsed.fragment and path.suffix == '.md':
        headings = re.findall(r'^#{1,6}\s+(.+)$', path.read_text(), re.M)
        if unquote(parsed.fragment) not in {slug(h) for h in headings}:
            raise ValueError(f'Broken heading anchor: {reference}')


def tree(path):
    module = group = None
    leaves = {}
    roots = 0
    for line in path.read_text().splitlines():
        heading = re.fullmatch(r'(#+) (.+)', line)
        if heading:
            level, label = len(heading[1]), heading[2]
            if level > 3:
                raise ValueError('ROADMAP permits only project/module/feature headings')
            if level == 1:
                roots += 1
                module = group = None
            elif level == 2:
                module, group = label, None
            else:
                if not module:
                    raise ValueError('Feature has no module')
                group = label
        leaf = re.fullmatch(r'- \[([ x])\] (.+)', line)
        if leaf:
            if not module or not group:
                raise ValueError('Only final feature items may have checkboxes')
            label = re.sub(r'（[^）]*）$', '', leaf[2])
            key = f'{module}/{group}/{label}'
            if key in leaves:
                raise ValueError(f'Duplicate leaf: {key}')
            leaves[key] = leaf[1] == 'x'
        elif re.search(r'\[[ xX]\]', line) or line.startswith('- '):
            raise ValueError('Use unindented, final-level checkboxes only')
    if roots != 1 or not leaves:
        raise ValueError('ROADMAP needs one project root and feature leaves')
    return leaves


def checkable(feature):
    version = feature['versions']['candidate']
    if not version or feature['blockers'] or feature['reopened']:
        raise ValueError(f"{feature['id']}: unresolved blockers or reopened defect")
    for key, status in [('review', 'passed'), ('acceptance', 'passed'), ('delivery', 'delivered')]:
        entry = feature[key]
        if entry['status'] != status or entry['version'] != version or not entry['evidence']:
            raise ValueError(f"{feature['id']}: {key} is not confirmed for candidate version")
    acceptance = feature['acceptance']
    if any(not acceptance.get(k) for k in ('environment', 'data', 'actor', 'date', 'steps', 'observed')):
        raise ValueError('Actual user-flow evidence needs environment/data/actor/date/steps/observations')
    if acceptance.get('kind') != 'actual-user-flow':
        raise ValueError('CI, mocks and source review cannot satisfy actual acceptance')
    design = feature.get('design', {})
    if design.get('required') and (design.get('status') != 'passed' or design.get('version') != version or not design.get('visual_evidence')):
        raise ValueError('UI feature needs actual visual verification for the candidate')
    target = feature['target']
    if target != 'local' and feature['versions'][target] != version:
        raise ValueError('Installed/online version does not match accepted candidate')


def historical_allowances(allowances, previous_leaves):
    if any(not previous_leaves.get(leaf, False) for leaf in allowances):
        raise ValueError('Historical allowance can cover only a previously checked leaf')


def validate(root, require=None, baseline=None):
    root = Path(root).resolve()
    config = json.loads((root / 'roadmap/_checks.json').read_text())
    roadmap = root / config['roadmap']
    leaves = tree(roadmap)
    if config.get('legacy_checked') and not baseline:
        raise ValueError('Historical allowances require --baseline-ref; do not skip baseline verification')
    if baseline:
        previous = subprocess.run(['git', '-C', str(root), 'show', f'{baseline}:{config["roadmap"]}'], capture_output=True, text=True, check=True).stdout
        # Parse the same tree without creating or executing a linked artifact.
        class PriorTree:
            def read_text(self):
                return previous
        historical_allowances(config.get('legacy_checked', {}), tree(PriorTree()))
    records, covered = {}, {}
    files = [root / 'docs/PRODUCT_WORKFLOW.md', roadmap, root / 'roadmap/README.md', root / 'roadmap/_template.md']
    for path in sorted((root / config['features']).glob('*.md')):
        if path.name.startswith('_') or path.name == 'README.md':
            continue
        text = path.read_text()
        blocks = re.findall(r'```product-feature\n(.*?)\n```', text, re.S)
        if len(blocks) != 1:
            raise ValueError(f'{path.name}: need one product-feature block')
        feature = json.loads(blocks[0])
        required = {'id', 'leaves', 'owner', 'sources', 'plan', 'versions', 'target', 'review', 'acceptance', 'delivery', 'blockers', 'reopened'}
        if not required <= feature.keys() or not feature['owner'] or not feature['sources'] or not feature['leaves']:
            raise ValueError(f'{path.name}: incomplete feature contract')
        if feature['id'] in records or path.stem != feature['id']:
            raise ValueError('Feature IDs must be unique and match filenames')
        if feature['target'] not in ('local', 'installed', 'online') or type(feature['reopened']) is not bool or not isinstance(feature['blockers'], list):
            raise ValueError('Invalid delivery target or defect state')
        if set(feature['versions']) != {'main', 'candidate', 'installed', 'online'}:
            raise ValueError('Separate main/candidate/installed/online versions')
        for version in feature['versions'].values():
            if version is not None and not SHA.fullmatch(version):
                raise ValueError('Use exact source SHA or null for unknown versions')
        for reference in [*feature['sources'], feature['plan']]:
            local_link(root, path, reference)
        for key, statuses in [('review', {'pending', 'passed', 'failed'}), ('acceptance', {'blocked', 'passed', 'failed'}), ('delivery', {'not-released', 'delivered', 'failed'})]:
            entry = feature[key]
            if entry.get('status') not in statuses or 'version' not in entry or 'evidence' not in entry:
                raise ValueError(f'Invalid {key} evidence fields')
            if entry['version'] is not None and not SHA.fullmatch(entry['version']):
                raise ValueError('Evidence needs an exact source SHA')
            if entry['evidence']:
                local_link(root, path, entry['evidence'])
            if entry['status'] in {'passed', 'delivered'} and (not entry['version'] or not entry['evidence']):
                raise ValueError(f'{key} claims pass without version and evidence')
        design = feature.get('design')
        if not isinstance(design, dict) or type(design.get('required')) is not bool:
            raise ValueError('Declare whether product design and visual verification are required')
        if design.get('status') not in {'pending', 'partial', 'passed'}:
            raise ValueError('Invalid product design status')
        for key in ('reference', 'visual_evidence'):
            if design.get(key):
                local_link(root, path, design[key])
        if design.get('status') == 'passed' and (not design.get('visual_evidence') or design.get('version') != feature['versions']['candidate']):
            raise ValueError('Design pass needs candidate visual evidence')
        for leaf in feature['leaves']:
            if leaf not in leaves or leaf in covered:
                raise ValueError(f'Unknown or multiply owned leaf: {leaf}')
            covered[leaf] = feature
            if leaves[leaf]:
                checkable(feature)
        records[feature['id']] = feature
        files.append(path)
    for leaf, proof in config.get('legacy_checked', {}).items():
        if leaf not in leaves or not proof.get('scope'):
            raise ValueError('Historical allowance must name an existing scoped leaf')
        local_link(root, root / 'baseline', proof['evidence'])
    for leaf, checked in leaves.items():
        if checked and leaf not in covered and leaf not in config.get('legacy_checked', {}):
            raise ValueError(f'Checked leaf has no actual acceptance: {leaf}')
    for path in files:
        # Template placeholder links are plain text, not fabricated Markdown links.
        for reference in re.findall(r'\[[^\]]*\]\(([^)]+)\)', path.read_text()):
            local_link(root, path, reference)
    if require:
        if require not in records:
            raise ValueError(f'Unknown feature: {require}')
        checkable(records[require])
    return len(leaves), len(records)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--require-checkable')
    parser.add_argument('--baseline-ref', help='Offline Git ref for historical checked-leaf comparison')
    args = parser.parse_args()
    try:
        leaves, records = validate(args.root, args.require_checkable, args.baseline_ref)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'ROADMAP gate failed: {error}\n')
    print(f'ROADMAP structure/evidence references valid: {leaves} leaves, {records} detailed features. Not a real acceptance result.')


if __name__ == '__main__':
    main()
