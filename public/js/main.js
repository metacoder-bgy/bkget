var base_uri = '';
// var base_uri = 'http://x.bgy.xxx/tools/bkget/';
var file_list = [];

$(document).ready(function() {
	$('#submit').click(submit);
	$('#video_url').on('keypress', function(e) {
		if(e.keyCode == 13) {
			submit();
			e.preventDefault();
		}
	});
	$(document).on('click', '#file_list li .icon-trash, #download_list li .icon-remove', function() {
		$.ajax({
			type: 'POST',
			url: base_uri + 'task/' + $(this).parents('li').first().attr('id').match(/^file_(.*)/)[1] + '/delete'
		});
	});
	$('#video_url').on('change keydown', hideWaring).focus();
	refresh();
	setInterval(refresh, 1000);
});

function refresh() {
	$.ajax({
		type: 'GET',
		url: base_uri + 'list',
		dataType: 'json',
		success: function(data) {
			file_list = data.list;
			renderFileList();
		},
		error: function(jqXHR, textStatus) {
		}
	});
}

function submit() {
	var url = $('#video_url').val();
	if($('#submit').hasClass('icon-spinner'))
		return;
	hideWaring();
	$('#submit').removeClass('icon-cloud-download').addClass('icon-spinner icon-spin');
	$.ajax({
		type: 'POST',
		url: base_uri + 'task',
		data: {
			url: url
		},
		statusCode: {
			400: badRequest,
			409: conflict,
			500: serverError
		},
		success: function(url) {
			return function() {
				$('#video_url').val('');
				hideWaring();
				refresh();
			};
		}(url),
		error: function(e,m) {
		},
		complete: function() {
			$('#submit').removeClass('icon-spinner icon-spin').addClass('icon-cloud-download');
		}
	});
}

function badRequest() {
	showWaring('The URL is invalid.');
}

function conflict() {
	showWaring('The task is conflicted.');
}

function serverError() {
	showWaring('A server error occured.');
}

function addItem(id, title, size) {
	if(! $('#file_list #file_' + id).length) {
		('#file_list').prepend(
			$('<li id="file_' + id + '">').append(
				$('<a href="' + getDownloadURL(id) + '" title="Download: ' + title + '">')
					.append($('<div class="icon-download-alt">'))
					.append($('<p class="title">' + title + '</p>'))
					.append($('<div class="size">' + humanReadableSize(size) + '</div>'))
			).append(
				$('<a class="icon-trash">')
			)
		);
	}
}

function humanReadableSize(bytes, si) {
    if (bytes < 1024) return bytes + ' B';
    var units = ['kB','MB','GB','TB'];
    var u = -1;
    do {
        bytes /= 1024;
        ++u;
    } while (bytes >= 1024);
    return bytes.toFixed(1) + units[u];
};

function humanReadableDate(unix_timestamp) {
	var date = new Date(unix_timestamp*1000),
		year = data.getFullYear(),
		month = date.getMonth(),
		day = date.getDate(),
		hour = date.getHours(),
		minute = date.getMinutes(),
		second = date.getSeconds();
	return year + '-' + padDigits(month, 2) + '-' + padDigits(day, 2) + ' ' +
		padDigits(hour, 2) + ':' + padDigits(minute, 2) + ':' + padDigits(second, 2);
}

function padDigits(n, totalDigits) {
	n = n.toString();
	var pd = '';
	if (totalDigits > n.length) {
		for (i=0; i < (totalDigits-n.length); i++) {
			pd += '0';
		}
	}
	return pd + n.toString();
}

function getDownloadURL(id) {
	return base_uri + 'task/' + id;
}

function showWaring(message) {
	$('#url_form').addClass('warning');
	$('.warning-box .message').html(message);
	$('.warning-box').removeClass('hidden').addClass('shown');
}

function hideWaring() {
	$('#url_form').removeClass('warning');
	$('.warning-box .message').html('');
	$('.warning-box').removeClass('shown').addClass('hidden');
}

function renderFileList() {
	if(!file_list.length) {

	}

	var status_order = {
		'downloading': 0,
		'finished': 1,
		'aborted': 2
	};

	$('#download_list li').each(function() {
		for(var i in file_list)
			if(file_list[i].id == this.id.match(/^file_(.*)/)[1] && file_list[i].status == 'downloading') return;
		$(this).hide('ease', function() {
			$(this).remove();
		});
	});

	$('#file_list li').each(function() {
		for(var i in file_list)
			if(file_list[i].id == this.id.match(/^file_(.*)/)[1]) return;
		$(this).hide('ease', function() {
			$(this).remove();
		});
	});

	$(file_list).sort(function(a,b) {
		status_order[a.status] - status_order[b.status];
	}).each(function() {
		if (this.status === 'downloading') {
			if($('#file_' + this.id).length) {
				$('#file_' + this.id + ' .ui-progress')
				.width(this.downloaded_size / this.total_size * 100 + '%');
				$('#file_' + this.id + ' .ui-label.progress').html(humanReadableSize(this.downloaded_size) + '/' + humanReadableSize(this.total_size) + ' ' + Math.floor(this.downloaded_size / this.total_size * 100) + '%');
				return;
			}
			$('#download_list').prepend(
				$('<li title="' + this.title + '" id="file_' + this.id + '" style="display:none;">')
				.append($('<div class="ui-progress-bar ui-container transition" id="progress_bar">')
					.append($('<div class="ui-progress" style="width: ' + this.downloaded_size / this.total_size * 100 + '%;">'))
					.append($('<span class="ui-label title">' + this.title + '</span>'))
					.append($('<span class="ui-label progress">' + humanReadableSize(this.downloaded_size) + '/' + humanReadableSize(this.total_size) + ' ' + Math.floor(this.downloaded_size / this.total_size * 100) + '%</span>'))
					.append($('<a class="icon-remove">')))
			);
		} else if (this.status === 'finished') {
			if($('#file_' + this.id).length)
				return;
			$('#file_list').prepend(
				$('<li id="file_' + this.id + '" style="display:none;">')
				.append($('<a href="' + getDownloadURL(this.id) + '" title="Download: ' + this.title + '" target="_blank" class="link">'))
				.append($('<a class="icon-link" title="Go to original website" target="_blank" href="' + this.original_url + '">'))
				.append($('<p class="title">' + this.title + '</p>'))
				.append($('<div class="size">' + humanReadableSize(this.total_size) + '</div>'))
				.append($('<a class="icon-trash" title="Delete">')));
		}
		$('#file_' + this.id).show('ease');
	});
}
