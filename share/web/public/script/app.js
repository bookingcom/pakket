// vim:ft=javascript

;(function(){
	const CSS_CLASS_PAKKET_BAD        = 'bad';
	const CSS_CLASS_PAKKET_FINE       = 'ok';
	const CSS_CLASS_PAKKET_MISSING    = 'missing';
	const CSS_CLASS_PAKKET_OUTDATED   = 'outdated';
	const CSS_CLASS_PAKKET_LATEST     = 'latest';
	const CSS_CLASS_PAKKET_NOT_LATEST = 'not-latest';
	const FLAG_GET_ONLY_BROKEN        = 'broken=1';
	const FLAG_GET_ONLY_OUTDATED      = 'outdated=1';
	const FLAG_GET_ONLY_NONCPAN       = 'noncpan=1';
	const RENDER_ONLY_BROKEN          = location.href.indexOf(FLAG_GET_ONLY_BROKEN) > -1 ? true : false;
	const RENDER_ONLY_OUTDATED        = location.href.indexOf(FLAG_GET_ONLY_OUTDATED) > -1 ? true : false;
	const RENDER_ONLY_NONCPAN         = location.href.indexOf(FLAG_GET_ONLY_NONCPAN) > -1 ? true : false;

	// extendable via the payload
	const COLUMNS_MANDATORY = ['spec', 'source'];
	const DOMAIN = 'booking';
	const DISPLAY_GITLAB_LINKS = window.location.hostname.indexOf('.' + DOMAIN + '.com') > -1 ? true : false;
	let desiredColumnsOrder = COLUMNS_MANDATORY;
	const urlPieces         = location.href.split('s=');
	const $onlyBrokenEl     = $('#only-problematic');
	const $onlyOutdatedEl   = $('#only-outdated');
	const $onlyNonCPANEl    = $('#only-non-cpan');
	const $searchEl         = $('#s_pakket');
	const $tbodyEl          = $('#tbody');
	let columnInfo          = {};
	let parcels; // parcels list we fetch from localSorage / BE once and do all further manipulations

	// changing 'only broken' checkbox ASAP
	if (RENDER_ONLY_BROKEN) {
		$onlyBrokenEl.attr('checked', 'checked');
	}
	if (RENDER_ONLY_OUTDATED) {
		$onlyOutdatedEl.attr('checked', 'checked');
	}
	if (RENDER_ONLY_NONCPAN) {
		$onlyNonCPANEl.attr('checked', 'checked');
	}
	// same thing with query string
	if (urlPieces.length === 2) {
		$searchEl.attr('value', urlPieces[1]);
	}

	// actual rendering packages call
	renderPackages();
	fetchVersion();

	function renderPackages() {
		const URL_FETCH_PAKKETS = '/all_packages';
		const localStorageKey = 'pakket-2020-07-30';
		// first checking if data is available at localStorage
		let pakketsInLocalStorage = localStorage.getItem(localStorageKey);
		if (pakketsInLocalStorage) {
			_renderUI(JSON.parse(pakketsInLocalStorage));
		}

		// updating cache if required
		$.ajax(URL_FETCH_PAKKETS).done(function(data) {
			const cachedPakketObject = JSON.stringify(data);
			if (pakketsInLocalStorage !== cachedPakketObject) {
				localStorage.setItem(localStorageKey, cachedPakketObject);
				_renderUI(data); // re-rendering UI
			}
		});
	}

	function fetchVersion() {
		const URL_FETCH_VERSION = '/info';
		const localStorageKey = 'pakket-version';
		// first checking if data is available at localStorage
		let pakketVersion = localStorage.getItem(localStorageKey);
		if (pakketVersion) {
			_renderVersion(pakketVersion);
		}

		// updating cache if required
		$.ajax(URL_FETCH_VERSION).done(function(data) {
			if (!data.version) return;
			const version = String(data.version);
			if (version !== pakketVersion) {
				localStorage.setItem(localStorageKey, version);
				// re-rendering UI
				_renderVersion(version);
			}
		});
	}

	/*
	 * Helper functions
	 **/

	function _renderUI(data) {
		// re-creating columnInfo
		columnInfo = {};
		// same regarding desiredColumnsOrder
		desiredColumnsOrder = COLUMNS_MANDATORY;

		parcels = new Map(Object.entries(data));

		// taking pakket #1 and getting columns metadata from it
		const first = parcels.values().next().value;
		const keys = Object.keys(first);
		keys.forEach((key) => {
			if (key === 'cpan' || key === 'cpan_version') {
				return;
			}
			if (desiredColumnsOrder.indexOf(key) === -1) {
				columnInfo[key] = [];
			}
			// getting OS metadata from first perl version prop
			if (strIsPerlVersion(key)){
				columnInfo[key] = Object.keys(first[key]).sort();
			}
		});

		desiredColumnsOrder = desiredColumnsOrder.concat(Object.keys(columnInfo).sort());

		let tableHead = '<tr>';
		tableHead += '<td class="name" rowspan="2" colspan="2">Distribution</td>';
		tableHead += '<td class="cpan" rowspan="2" colspan="1"><a target="_blank" href="/updates">Updates</a></td>';
		desiredColumnsOrder.forEach((column) => {
			// calculating colspan and rowspan
			let colspan = 1;
			let rowspan = 1;
			if (strIsPerlVersion(column)){
				// making sure we display as many OSes under certain perl version
				// as BE gives us in output
				colspan = columnInfo[column].length;
			} else {
				rowspan = 2;
			}
			tableHead += `<td colspan="${colspan}" rowspan="${rowspan}">${column}</td>`;
		});
		tableHead += '</tr><tr>';
		desiredColumnsOrder.forEach((column) => {
			if (!strIsPerlVersion(column)) return;
			columnInfo[column].forEach((os) => {
				tableHead += `<td>${os}</td>`;
			});
		});
		tableHead += '</tr>';
		// showing page title
		$('.hidden').removeClass('hidden');
		// required on re-render
		$('#thead').empty();
		$('#thead').append(tableHead);

		// making payload available globally
		_renderTableBody();
	}

	function _renderVersion(version) {
		$('#pakket-uwsgi-version').text(version);
		$('.pakket-uwsgi-version').show();
	}

	function _renderTableBody() {
		// by default rendering whole list of parcels
		const onlyBroken   = location.href.indexOf(FLAG_GET_ONLY_BROKEN) > -1 ? true : false;;
		const onlyOutdated = location.href.indexOf(FLAG_GET_ONLY_OUTDATED) > -1 ? true : false;;
		const onlyNonCPAN  = location.href.indexOf(FLAG_GET_ONLY_NONCPAN) > -1 ? true : false;;
		let searchQuery    = $searchEl.val();
		searchQuery = searchQuery ? searchQuery.trim() : '';
		searchQuery = searchQuery.toLowerCase();
		searchQuery = searchQuery.replace(/::/g,'-');

		let ids = Array.from(parcels.keys()).sort();

		if (searchQuery.length) { // filtering by name
			let filtered = new Array;
			ids.forEach((id) => {
				if (id.toLowerCase().indexOf(searchQuery) > -1) {
					filtered.push(id);
				}
			});
			ids = filtered;
		}

		if (onlyOutdated) {
			let filtered = new Array;
			ids.forEach((id) => {
				const pakket = parcels.get(id);
				if ('cpan_version' in pakket) {
					filtered.push(id);
				}
			});
			ids = filtered;
		}

		if (onlyNonCPAN) {
			let filtered = new Array;
			ids.forEach((id) => {
				const pakket = parcels.get(id);
				if (!('cpan' in pakket)) {
					filtered.push(id);
				}
			});
			ids = filtered;
		}

		if (onlyBroken) { // filtering out only broken if it's a case
			let filtered = new Array;
			ids.forEach((id) => {
				const pakket = parcels.get(id);
				let isBroken = false;
				Object.values(pakket).forEach((value) => {
					if (typeof value !== 'object') {
						if (value === 0) {
							isBroken = true;
							return;
						}
					} else {
						if (Object.values(value).filter(val => val === 0).length > 0) {
							isBroken = true;
						}
					}
				});

				if (isBroken) {
					filtered.push(id);
				}
			});
			ids = filtered;
		}

		// calculating and rendering body
		let tableBody = '';
		const pakketsMap = new Map();

		// calculating pakketsMap - no rendering yet
		ids.forEach((id) => {
			const nameFull = id;
			const namePieces = nameFull.split('=');
			const nameShort = namePieces[0];
			const version = namePieces[1];
			let mapVersions = pakketsMap.get(nameShort);
			mapVersions = mapVersions || [];
			if (mapVersions) {
				mapVersions.push(version);
			}
			pakketsMap.set(nameShort, mapVersions);
		});
		// actual rendering to a string
		ids.forEach((id) => {
			const pakket = parcels.get(id);
			const namePieces = id.split('=');
			tableBody += columnRenderer({
				name: namePieces[0],
				version: namePieces[1],
				order: desiredColumnsOrder,
				data: pakket,
				versions_all: pakketsMap.get(namePieces[0])
			});
		});

		// required on re-render
		$tbodyEl.empty();
		$tbodyEl.append(`${tableBody}`);
	}

	// Is the string containing Perl version?
	function strIsPerlVersion(str) {
		return !isNaN(parseInt(str));
	}

	// GET query creator
	function composeGetQuery() {
		const search = $searchEl.val().toLowerCase();
		const params = [];
		if ($onlyBrokenEl.is(':checked')) {
			params.push(FLAG_GET_ONLY_BROKEN);
		}
		if ($onlyOutdatedEl.is(':checked')) {
			params.push(FLAG_GET_ONLY_OUTDATED);
		}
		if ($onlyNonCPANEl.is(':checked')) {
			params.push(FLAG_GET_ONLY_NONCPAN);
		}
		if (search.length) {
			params.push(`s=${search}`);
		}
		let getQuery = '/status';
		params.forEach((param, index) => {
			const separator = index === 0 ? '?' : '&';
			getQuery += `${separator}${param}`;
		});
		return getQuery;
	}

	// Pakket table column renderer
	function columnRenderer(config) {
		const renderQueue = [];
		let problematicPakket = false;
		let versionsUI = '';
		const versionsArr = config.versions_all;
		versionsArr.forEach((version) => {
			versionsUI += `<option value="${version}" ${(version === config.version) ? 'selected' : ''}>${version}</option>`;
		});
		let name = config.name;

		if (DISPLAY_GITLAB_LINKS) {
			name = `<a target="_blank" title="${name}"
				href="https://gitlab.` + DOMAIN + `.com/packaging/pakket/meta/-/tree/master/${name}.yaml">${name}</a>`;
		}

		const namePieces = config.name.split('/');
		let cpan_version = config.data['cpan_version'] ? config.data['cpan_version'] : '';
		cpan_version = `<a target="_blank" title="" href="https://fastapi.metacpan.org/release/${namePieces[1]}">${cpan_version}</a>`;

		let icon
			= config.data['cpan']
			? `<a target="_blank" title="${namePieces[1]}" href="https://metacpan.org/release/${namePieces[1]}"><img src="/image/metacpan-icon.png"</img></a>`
			: '';

		let tableRow = `
			<td class="name">${name}</td>
			<td class="version">${(versionsArr.length === 1 ? versionsArr[0] : ('<select data-name="' + config.name.replace(/[\/\.\:]/g,'') + '">' + versionsUI + '</select>'))}</td>
			<td class="${config.data['cpan_version'] ? 'outdated' : 'none'}">${icon} ${cpan_version}</td>
		`;
		config.order.forEach((column) => {
			if (strIsPerlVersion(column)) {
				columnInfo[column].forEach((os) => {
					renderQueue.push((config.data[column] && config.data[column][os]) ? '+' : '-');
				});
			} else {
				renderQueue.push(config.data[column] ? '+' : '-');
			}
		});
		// rendering queue
		renderQueue.forEach((val) => {
			tableRow += `<td ${(val === '+' ? '' : ('class="' + CSS_CLASS_PAKKET_MISSING + '"'))}>${val}</td>`;
		});
		// figuring out if pakket is problematic + reflecting in <tr> css class
		problematicPakket = !!renderQueue.filter(val => val === '-').length;
		const latestVersion = config.versions_all[config.versions_all.length - 1];
		return `<tr ${config.version !== latestVersion ? 'style="display: none;"' : ''}
			id="pak--${config.name.replace(/[\/\.\:]/g,'')}-${config.version.replace(/[\/\.\:]/g,'')}"
			class="${problematicPakket ? CSS_CLASS_PAKKET_BAD : CSS_CLASS_PAKKET_FINE}
						${config.version === latestVersion ? CSS_CLASS_PAKKET_LATEST : CSS_CLASS_PAKKET_NOT_LATEST}">${tableRow}</tr>`;
	}

	// search helper
	function search() {
		window.history.pushState('', '', composeGetQuery());
		const search = $searchEl.val().toLowerCase();
		_renderTableBody();
	}

	$tbodyEl.on('change', '.version select', function(e){
		const $target = $(e.target);
		const value = $target.val();
		const pakketName = $target.data('name');
		const $currRow = $target.parents('tr');
		const $select = $currRow.find('select');
		// hiding current row
		$currRow.hide();
		// re-shaking select UI
		const selectOptions = $select.html();
		$select.html(selectOptions);
		// showing new one
		$(`#pak--${pakketName}-${value.replace(/[\/\.\:]/g,'')}`).show();
	});

	$onlyBrokenEl.on('change', function(){
		if ($(this).is(':checked')) {
			// reflecting change in URL
			window.history.pushState('', '', composeGetQuery());
		} else {
			// reflecting change in URL
			window.history.replaceState('', '', composeGetQuery());
		}
		_renderTableBody();
	});

	$onlyOutdatedEl.on('change', function(){
		if ($(this).is(':checked')) {
			// reflecting change in URL
			window.history.pushState('', '', composeGetQuery());
		} else {
			// reflecting change in URL
			window.history.replaceState('', '', composeGetQuery());
		}
		_renderTableBody();
	});

	$onlyNonCPANEl.on('change', function(){
		if ($(this).is(':checked')) {
			// reflecting change in URL
			window.history.pushState('', '', composeGetQuery());
		} else {
			// reflecting change in URL
			window.history.replaceState('', '', composeGetQuery());
		}
		_renderTableBody();
	});

	// search DOM handler
	let timeout;
	$searchEl.on('input', function(){
		const TIMEOUT = 200;
		if ((new Date().getTime() - timeout) < TIMEOUT) clearTimeout(timeout);
		timeout = setTimeout(search, TIMEOUT);
	});
})();
