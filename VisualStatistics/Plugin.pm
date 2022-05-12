#
# Visual Statistics
#
# (c) 2021-2022 AF-1
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#

package Plugins::VisualStatistics::Plugin;

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Schema;
use JSON::XS;
use URI::Escape;
use Time::HiRes qw(time);
use Data::Dumper;

use Plugins::VisualStatistics::Settings;
use constant LIST_URL => 'plugins/VisualStatistics/html/list.html';
use constant JSON_URL => 'plugins/VisualStatistics/getdata.html';

my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.visualstatistics',
	'defaultLevel' => 'WARN',
	'description' => 'PLUGIN_VISUALSTATISTICS',
});
my $serverPrefs = preferences('server');
my $prefs = preferences('plugin.visualstatistics');
my %ignoreCommonWords;
my $rowLimit = 50;

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	if (!$::noweb) {
		require Plugins::VisualStatistics::Settings;
		Plugins::VisualStatistics::Settings->new();
	}
	initPrefs();
	Slim::Web::Pages->addPageFunction(LIST_URL, \&handleWeb);
	Slim::Web::Pages->addPageFunction(JSON_URL, \&handleJSON);
	Slim::Web::Pages->addPageLinks('plugins', {'PLUGIN_VISUALSTATISTICS' => LIST_URL});
}

sub initPrefs {
	$prefs->init({
		displayapcdupes => 1,
		minartisttracks => 3,
		minalbumtracks => 3,
	});
	my $apc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::AlternativePlayCount::Plugin');
	if (!$apc_enabled && $prefs->get('displayapcdupes') == 2) {
		$prefs->set('displayapcdupes', 1);
	}
	$prefs->set('selectedvirtuallibrary', '');
	%ignoreCommonWords = map {
		$_ => 1
	} ("able", "about", "above", "acoustic", "act", "adagio", "after", "again", "against", "ago", "ain", "air", "akt", "album", "all", "allegretto", "allegro", "alone", "also", "alt", "alternate", "always", "among", "and", "andante", "another", "any", "are", "aria", "around", "atto", "autre", "away", "baby", "back", "bad", "beat", "because", "been", "before", "behind", "believe", "better", "big", "black", "blue", "bonus", "boy", "bring", "but", "bwv", "call", "can", "cause", "came", "chanson", "che", "chorus", "club", "come", "comes", "comme", "con", "concerto", "cosa", "could", "couldn", "dans", "das", "day", "days", "deezer", "dein", "del", "demo", "den", "der", "des", "did", "didn", "die", "does", "doesn", "don", "done", "down", "dub", "dur", "each", "edit", "ein", "either", "else", "end", "est", "even", "ever", "every", "everybody", "everything", "extended", "feat", "featuring", "feel", "find", "first", "flat", "for", "from", "fur", "get", "girl", "give", "going", "gone", "gonna", "good", "got", "gotta", "had", "hard", "has", "have", "hear", "heart", "her", "here", "hey", "him", "his", "hit", "hold", "home", "how", "ich", "iii", "inside", "instrumental", "interlude", "into", "intro", "isn", "ist", "just", "keep", "know", "las", "last", "leave", "left", "les", "let", "life", "like", "little", "live", "long", "look", "los", "love", "made", "major", "make", "man", "master", "may", "medley", "mein", "meu", "might", "mind", "mine", "minor", "miss", "mix", "moderato", "moi", "moll", "molto", "mon", "mono", "more", "most", "move", "much", "music", "must", "myself", "name", "nao", "near", "need", "never", "new", "nicht", "nobody", "non", "not", "nothing", "now", "off", "old", "once", "one", "only", "ooh", "orchestra", "original", "other", "ouh", "our", "ours", "out", "over", "own", "part", "pas", "people", "piano", "place", "play", "please", "plus", "por", "pour", "prelude", "presto", "put", "quartet", "que", "qui", "quite", "radio", "rather", "real", "really", "recitativo", "recorded", "remix", "right", "rock", "roll", "run", "said", "same", "sao", "say", "scene", "see", "seem", "session", "she", "should", "shouldn", "side", "single", "skit", "solo", "some", "something", "somos", "son", "sonata", "song", "sous", "spotify", "start", "stay", "stereo", "still", "stop", "street", "such", "suite", "symphony", "szene", "take", "talk", "teil", "tel", "tell", "tempo", "than", "that", "the", "their", "them", "then", "there", "these", "they", "thing", "things", "think", "this", "those", "though", "thought", "three", "through", "thus", "till", "time", "titel", "together", "told", "tonight", "too", "track", "trio", "true", "try", "turn", "two", "una", "und", "under", "une", "until", "use", "version", "very", "vivace", "vocal", "walk", "wanna", "want", "was", "way", "well", "went", "were", "what", "when", "where", "whether", "which", "while", "who", "whose", "why", "will", "with", "without", "woman", "won", "woo", "world", "would", "wrong", "yeah", "yes", "yet", "you", "your");
}

sub handleWeb {
	my ($client, $params, $callback, $httpClient, $httpResponse, $request) = @_;
	$prefs->set('genrefilterid', '');
	$prefs->set('decadefilterval', '');
	$prefs->set('selectedvirtuallibrary', '');
	$params->{'vlselect'} = $prefs->get('selectedvirtuallibrary');

	my $host = $params->{host} || (Slim::Utils::Network::serverAddr() . ':' . preferences('server')->get('httpport'));
	$params->{'squeezebox_server_jsondatareq'} = 'http://' . $host . '/jsonrpc.js';

	my $ratedTrackCountSQL = "select count(distinct tracks.id) from tracks,tracks_persistent where tracks_persistent.urlmd5 = tracks.urlmd5 and tracks.audio = 1 and tracks_persistent.rating > 0";
	my $ratedTrackCount = quickSQLcount($ratedTrackCountSQL) || 0;
	$params->{'ratedtrackcount'} = $ratedTrackCount;

	$params->{'virtuallibraries'} = getVirtualLibraries();
	$params->{'librarygenres'} = getGenres();

	my $apc_enabled = Slim::Utils::PluginManager->isEnabled('Plugins::AlternativePlayCount::Plugin');
	$params->{'apcenabled'} = 'yes' if $apc_enabled;
	$params->{'displayapcdupes'} = $prefs->get('displayapcdupes');
	$params->{'usefullscreen'} = $prefs->get('usefullscreen') ? 1 : 0;

	return Slim::Web::HTTP::filltemplatefile($params->{'path'}, $params);
}

sub handleJSON {
	my ($client, $params, $callback, $httpClient, $httpResponse, $request) = @_;
	my $response = {error => 'invalid arguments'};

	my $paramContents = decode_json($params->{content});
	$log->debug('paramContents = '.Dumper($paramContents));
	my $querytype = $paramContents->{'type'};
	my $list = $paramContents->{'list'};

	my $started = time();

	if ($querytype) {
		$response = {
			error => 0,
			msg => $querytype,
			results => eval("$querytype()"),
		};
	}

	if ($list) {
		$response = {
			error => 0,
			msg => $list,
		};
		if ($list eq 'decadelist') {
			$response = {
				results => getDecades(),
			};
		}

		if ($list eq 'genrelist') {
			$response = {
				results => getGenres(),
			};
		}
	}

	$log->debug('JSON response = '.Dumper($response));
	$log->info('exec time for query "'.$querytype.'" = '.(time()-$started).' seconds.') if $querytype;
	my $content = $params->{callback} ? $params->{callback}.'('.JSON::XS->new->ascii->encode($response).')' : JSON::XS->new->ascii->encode($response);
	$httpResponse->header('Content-Length' => length($content));

	return \$content;
}

## ---- library stats text ---- ##

sub getDataLibStatsText {
	my @result = ();
	my $selectedVL = $prefs->get('selectedvirtuallibrary');

	my $VLname = Slim::Music::VirtualLibraries->getNameForId($selectedVL) || string("PLUGIN_VISUALSTATISTICS_VL_COMPLETELIB_NAME");
	push (@result, {'name' => 'vlheadername', 'value' => Slim::Utils::Unicode::utf8decode($VLname, 'utf8')});

	# number of tracks
	my $trackCountSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$trackCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$trackCountSQL .= " where tracks.audio = 1 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCount = quickSQLcount($trackCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALTRACKS").':', 'value' => $trackCount});

	# number of local tracks/files
	my $trackCountLocalSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$trackCountLocalSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$trackCountLocalSQL .= " where tracks.audio = 1 and tracks.remote = 0 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCountLocal = quickSQLcount($trackCountLocalSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALTRACKSLOCAL").':', 'value' => $trackCountLocal});

	# number of remote tracks
	my $trackCountRemoteSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$trackCountRemoteSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$trackCountRemoteSQL .= " where tracks.audio =1 and tracks.remote = 1 and tracks.extid is not null and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCountRemote = quickSQLcount($trackCountRemoteSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALTRACKSREMOTE").':', 'value' => $trackCountRemote});

	# total playing time
	my $totalTimeSQL = "select sum(secs) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$totalTimeSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$totalTimeSQL .=" where tracks.audio = 1 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $totalTime = prettifyTime(quickSQLcount($totalTimeSQL));
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALPLAYINGTIME").':', 'value' => $totalTime});

	# total library size
	my $totalLibrarySizeSQL = "select round((sum(filesize)/1024/1024/1024),2)||' GB' from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$totalLibrarySizeSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$totalLibrarySizeSQL .= " where tracks.audio = 1 and tracks.remote = 0 and tracks.filesize is not null";
	my $totalLibrarySize = quickSQLcount($totalLibrarySizeSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALLIBSIZE").':', 'value' => $totalLibrarySize});

	# library age
	my $libraryAgeinSecsSQL = "select (strftime('%s', 'now', 'localtime') - min(tracks_persistent.added)) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$libraryAgeinSecsSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$libraryAgeinSecsSQL .= " join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5 where tracks.audio = 1";
	my $libraryAge = prettifyTime(quickSQLcount($libraryAgeinSecsSQL));
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TOTALIBAGE").':', 'value' => $libraryAge});

	# number of artists
	my $artistCountSQL = "select count(distinct contributor_track.contributor) from contributor_track";
	if ($selectedVL && $selectedVL ne '') {
		$artistCountSQL .= " join tracks on tracks.id = contributor_track.track join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$artistCountSQL .= " where contributor_track.role in (1,5,6)";
	my $artistCount = quickSQLcount($artistCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTS").':', 'value' => $artistCount});

	# number of album artists
	my $albumArtistCountSQL = "select count(distinct contributor_track.contributor) from contributor_track";
	if ($selectedVL && $selectedVL ne '') {
		$albumArtistCountSQL .= " join tracks on tracks.id = contributor_track.track join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$albumArtistCountSQL .= " where contributor_track.role = 5";
	my $albumArtistCount = quickSQLcount($albumArtistCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_AARTISTS").':', 'value' => $albumArtistCount});

	# number of composers
	my $composerCountSQL = "select count(distinct contributor_track.contributor) from contributor_track";
	if ($selectedVL && $selectedVL ne '') {
		$albumArtistCountSQL .= " join tracks on tracks.id = contributor_track.track join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$albumArtistCountSQL .= " where contributor_track.role = 2";
	my $composerCount = quickSQLcount($composerCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_COMPOSERS").':', 'value' => $composerCount});

	# number of artists played
	my $artistsPlayedSQL = "select count(distinct contributor_track.contributor) from contributor_track
		join tracks on
			tracks.id = contributor_track.track";
	if ($selectedVL && $selectedVL ne '') {
		$artistsPlayedSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$artistsPlayedSQL .= " join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5 and tracks_persistent.playcount > 0
		where
			tracks.audio = 1
			and contributor_track.role in (1,5,6)";
	my $artistsPlayedFloat = quickSQLcount($artistsPlayedSQL)/$artistCount * 100;
	my $artistsPlayedPercentage = sprintf("%.1f", $artistsPlayedFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ARTISTSPLAYED").':', 'value' => $artistsPlayedPercentage});

	# number of albums
	my $albumsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$albumsCountSQL .= " where tracks.audio = 1";
	my $albumsCount = quickSQLcount($albumsCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMS").':', 'value' => $albumsCount});

	# number of compilations
	my $compilationsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$compilationsCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$compilationsCountSQL .= " where tracks.audio = 1 and albums.compilation = 1";
	my $compilationsCountFloat = quickSQLcount($compilationsCountSQL)/$albumsCount * 100;
	my $compilationsCountPercentage = sprintf("%.1f", $compilationsCountFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_COMPIS").':', 'value' => $compilationsCountPercentage});

	# number of artist albums
	my $artistAlbumsCountSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$artistAlbumsCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$artistAlbumsCountSQL .= " where tracks.audio = 1 and (albums.compilation is null or albums.compilation = 0)";
	my $artistAlbumsCount = quickSQLcount($artistAlbumsCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_AALBUMS").':', 'value' => $artistAlbumsCount});

	# number of albums played
	my $albumsPlayedSQL = "select count(distinct albums.id) from albums
		join tracks on
			tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsPlayedSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
		$albumsPlayedSQL .= " join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.audio = 1
			and tracks_persistent.playcount > 0";
	my $albumsPlayedFloat = quickSQLcount($albumsPlayedSQL)/$albumsCount * 100;
	my $albumsPlayedPercentage = sprintf("%.1f", $albumsPlayedFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSPLAYED").':', 'value' => $albumsPlayedPercentage});

	# number of albums without artwork
	my $albumsNoArtworkSQL = "select count(distinct albums.id) from albums join tracks on tracks.album = albums.id";
	if ($selectedVL && $selectedVL ne '') {
		$albumsNoArtworkSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$albumsNoArtworkSQL .= " where tracks.audio = 1 and albums.artwork is null";
	my $albumsNoArtwork = quickSQLcount($albumsNoArtworkSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_ALBUMSNOARTWORK").':', 'value' => $albumsNoArtwork});

	# number of genres
	my $genreCountSQL = "select count(distinct genre_track.genre) from genre_track";
	if ($selectedVL && $selectedVL ne '') {
		$genreCountSQL .= " join tracks on tracks.id = genre_track.track join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreCount = quickSQLcount($genreCountSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_GENRES").':', 'value' => $genreCount});

	# number of lossless tracks
	my $losslessTrackCountSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$losslessTrackCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$losslessTrackCountSQL .= " where tracks.audio = 1 and tracks.lossless = 1";
	my $losslessTrackCountFloat = quickSQLcount($losslessTrackCountSQL)/$trackCount * 100;
	my $losslessTrackCountPercentage = sprintf("%.1f", $losslessTrackCountFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_LOSSLESS").':', 'value' => $losslessTrackCountPercentage});

	# number of rated tracks
	my $ratedTrackCountSQL = "select count(distinct tracks.id) from tracks, tracks_persistent";
	if ($selectedVL && $selectedVL ne '') {
		$ratedTrackCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$ratedTrackCountSQL .= " where tracks_persistent.urlmd5 = tracks.urlmd5 and tracks.audio = 1 and tracks_persistent.rating > 0";
	my $ratedTrackCount = quickSQLcount($ratedTrackCountSQL);
	my $ratedTrackCountPercentage = sprintf("%.1f", ($ratedTrackCount/$trackCount * 100)).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_RATEDTRACKS").':', 'value' => $ratedTrackCountPercentage});

	# number of tracks played at least once
	my $songsPlayedOnceSQL = "select count(distinct tracks.id) from tracks join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5";
	if ($selectedVL && $selectedVL ne '') {
		$songsPlayedOnceSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$songsPlayedOnceSQL .= " where tracks.audio = 1 and tracks_persistent.playcount > 0";
	my $songsPlayedOnceFloat = quickSQLcount($songsPlayedOnceSQL)/$trackCount * 100;
	my $songsPlayedOncePercentage = sprintf("%.1f", $songsPlayedOnceFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSPLAYED").':', 'value' => $songsPlayedOncePercentage});

	# total play count
	my $songsPlayedTotalSQL = "select sum(tracks_persistent.playcount) from tracks join tracks_persistent on tracks_persistent.urlmd5 = tracks.urlmd5";
	if ($selectedVL && $selectedVL ne '') {
		$songsPlayedTotalSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$songsPlayedTotalSQL .= " where tracks.audio = 1 and tracks_persistent.playcount > 0";
	my $songsPlayedTotal = quickSQLcount($songsPlayedTotalSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSPLAYCOUNTTOTAL").':', 'value' => $songsPlayedTotal});

	# average track length
	my $avgTrackLengthSQL = "select strftime('%M:%S', avg(secs)/86400.0) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$avgTrackLengthSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$avgTrackLengthSQL .= " where tracks.audio = 1";
	my $avgTrackLength = quickSQLcount($avgTrackLengthSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSAVGLENGTH").':', 'value' => $avgTrackLength.' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEMINS")});

	# average bit rate
	my $avgBitrateSQL = "select round((avg(bitrate)/10000)*10) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$avgBitrateSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$avgBitrateSQL .= " where tracks.audio = 1 and tracks.bitrate is not null";
	my $avgBitrate = quickSQLcount($avgBitrateSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_AVGBITRATE").':', 'value' => $avgBitrate.' kbps'});

	# average file size
	my$avgFileSizeSQL = "select round((avg(filesize)/(1024*1024)), 2)||' MB' from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$avgFileSizeSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$avgFileSizeSQL .= " where tracks.audio = 1 and tracks.remote=0 and tracks.filesize is not null";
	my $avgFileSize = quickSQLcount($avgFileSizeSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_AVGFILESIZE").':', 'value' => $avgFileSize});

	# number of tracks with lyrics
	my $tracksWithLyricsSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$tracksWithLyricsSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$tracksWithLyricsSQL .= " where tracks.audio = 1 and tracks.lyrics is not null";
	my $tracksWithLyricsFloat = quickSQLcount($tracksWithLyricsSQL)/$trackCount * 100;
	my $tracksWithLyricsPercentage = sprintf("%.1f", $tracksWithLyricsFloat).'%';
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSWITHLYRICS").':', 'value' => $tracksWithLyricsPercentage});

	# number of tracks without replay gain
	my $tracksNoReplayGainSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$tracksNoReplayGainSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$tracksNoReplayGainSQL .= " where tracks.audio = 1 and tracks.filesize is not null and tracks.replay_gain is null";
	my $tracksNoReplayGain = quickSQLcount($tracksNoReplayGainSQL);
	push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TRACKSNOREPLAYGAIN").':', 'value' => $tracksNoReplayGain});

	# number of tracks for each mp3 tag version
	my $mp3tagversionsSQL = "select tracks.tagversion as thistagversion, count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$mp3tagversionsSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$mp3tagversionsSQL .= " where tracks.audio=1 and tracks.content_type = 'mp3' and tracks.tagversion is not null group by tracks.tagversion";
	my $mp3tagversions = executeSQLstatement($mp3tagversionsSQL);
	my @sortedmp3tagversions = sort { $a->{'xAxis'} cmp $b->{'xAxis'} } @{$mp3tagversions};
	foreach my $thismp3tagversion (@sortedmp3tagversions) {
		push (@result, {'name' => string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_MP3TRACKSTAGS").' '.$thismp3tagversion->{'xAxis'}.' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TAGS").':', 'value' => $thismp3tagversion->{'yAxis'}});
	}

	$log->debug(Dumper(\@result));
	return \@result;
}


## ---- library stats charts ---- ##

# ---- tracks ---- #

sub getDataTracksByAudioFileFormat {
	my $sqlstatement = "select tracks.content_type, count(distinct tracks.id) as nooftypes from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			tracks.audio = 1";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.content_type
		order by nooftypes desc";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByBitrate {
	my $sqlstatement = "select round(bitrate/16000)*16, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			tracks.audio = 1
			and tracks.bitrate is not null
			and tracks.bitrate > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by (case
			when round(tracks.bitrate/16000)*16 > 1400 then round(tracks.bitrate/160000)*160
			when round(tracks.bitrate/16000)*16 < 10 then 16
			else round(tracks.bitrate/16000)*16
			end)
		order by tracks.bitrate asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksBySampleRate {
	my $sqlstatement = "select tracks.samplerate||' Hz',count(distinct tracks.id) from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			tracks.audio = 1
			and tracks.samplerate is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.samplerate||' Hz'
		order by tracks.samplerate asc;";

	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByBitrateAudioFileFormat {
	my $dbh = getCurrentDBH();
	my @result = ();
	my $genreFilter = $prefs->get('genrefilterid');
	my @fileFormatsWithBitrate = ();
	my $xLabelTresholds = [[1, 192], [192, 256], [256, 320], [320, 500], [500, 700], [700, 1000], [1000, 1201], [1201, 999999999999]];
	foreach my $xLabelTreshold (@{$xLabelTresholds}) {
		my $minVal = @{$xLabelTreshold}[0];
		my $maxVal = @{$xLabelTreshold}[1];
		my $xLabelName = '';
		if (@{$xLabelTreshold}[0] == 1) {
			$xLabelName = '<'.@{$xLabelTreshold}[1];
		} elsif (@{$xLabelTreshold}[1] == 999999999999) {
			$xLabelName = '>'.(@{$xLabelTreshold}[0]-1);
		} else {
			$xLabelName = @{$xLabelTreshold}[0]."-".((@{$xLabelTreshold}[1])-1);
		}
		my $subData = '';
		my $sqlbitrate = "select tracks.content_type, count(distinct tracks.id) as nooftracks from tracks";
		my $selectedVL = $prefs->get('selectedvirtuallibrary');
		if ($selectedVL && $selectedVL ne '') {
			$sqlbitrate .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
		}
		if (defined($genreFilter) && $genreFilter ne '') {
			$sqlbitrate .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
		}
		$sqlbitrate .= " where
				tracks.audio = 1
				and tracks.bitrate is not null
				and round(tracks.bitrate/10000)*10 >= $minVal
				and round(tracks.bitrate/10000)*10 < $maxVal";
		my $decadeFilterVal = $prefs->get('decadefilterval');
		if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
			$sqlbitrate .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
		}
		$sqlbitrate .= " and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir')
			group by tracks.content_type
			order by tracks.content_type asc";
		my $sth = $dbh->prepare($sqlbitrate);
		#eval {
			$sth->execute();
			my $xAxisDataItem; # string values
			my $yAxisDataItem; # numeric values
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem);
				$subData = $subData.', "'.$xAxisDataItem.'": '.$yAxisDataItem;
				push(@fileFormatsWithBitrate, $xAxisDataItem) unless grep{$_ eq $xAxisDataItem} @fileFormatsWithBitrate;
			}
			$sth->finish();
			$subData = '{"x": '.'"'.$xLabelName.'"'.$subData.'}';
			push(@result, $subData);
		#};
	}

	my $sqlfileformats = "select distinct tracks.content_type from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlfileformats .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlfileformats .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlfileformats .= " where
			tracks.audio = 1
			and tracks.remote = 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlfileformats .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlfileformats .= " and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir')
		group by tracks.content_type
		order by tracks.content_type asc";
	my @fileFormatsComplete = ();
	my @fileFormatsNoBitrate = ();
	my $fileFormatName;
	my $sth = $dbh->prepare($sqlfileformats);
	$sth->execute();
	$sth->bind_columns(undef, \$fileFormatName);
	while ($sth->fetch()) {
		push (@fileFormatsComplete, $fileFormatName);
		push (@fileFormatsNoBitrate, $fileFormatName) unless grep{$_ eq $fileFormatName} @fileFormatsWithBitrate;
	}
	$sth->finish();
	my $subDataOthers = '';
	if (scalar(@fileFormatsNoBitrate) > 0) {
		foreach my $fileFormatNoBitrate (@fileFormatsNoBitrate) {
			my $sqlfileformatsnobitrate = "select count(distinct tracks.id) from tracks";
			my $selectedVL = $prefs->get('selectedvirtuallibrary');
			if ($selectedVL && $selectedVL ne '') {
				$sqlfileformatsnobitrate .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
			}
			if (defined($genreFilter) && $genreFilter ne '') {
				$sqlfileformatsnobitrate .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
			}
			$sqlfileformatsnobitrate .= " where tracks.audio = 1 and tracks.content_type=\"$fileFormatNoBitrate\"";
			my $decadeFilterVal = $prefs->get('decadefilterval');
			if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
				$sqlfileformatsnobitrate .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
			}
			my $sth = $dbh->prepare($sqlfileformatsnobitrate);
			my $fileFormatCount = 0;
			$sth->execute();
			$sth->bind_columns(undef, \$fileFormatCount);
			$sth->fetch();
			$sth->finish();
			$subDataOthers = $subDataOthers.', "'.$fileFormatNoBitrate.'": '.$fileFormatCount;
		}
		$subDataOthers = '{"x": "'.string("PLUGIN_VISUALSTATISTICS_CHARTLABEL_NOBITRATE").'"'.$subDataOthers.'}';
		push(@result, $subDataOthers);
	}

	my @wrapper = (\@result, \@fileFormatsComplete);
	$log->debug('wrapper = '.Dumper(\@wrapper));

	return \@wrapper;
}

sub getDataTracksByBitrateAudioFileFormatScatter {
	my $dbh = getCurrentDBH();
	my @result = ();
	my $sqlfileformats = "select distinct tracks.content_type from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlfileformats .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlfileformats .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlfileformats .= " where
			tracks.audio = 1
			and tracks.bitrate is not null
			and tracks.bitrate > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlfileformats .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlfileformats .= " and (tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir')
		group by tracks.content_type
		order by tracks.content_type asc";
	my @fileFormatsComplete = ();
	my @bitRates = ();
	my $fileFormatName;
	my $sth = $dbh->prepare($sqlfileformats);
	$sth->execute();
	$sth->bind_columns(undef, \$fileFormatName);
	while ($sth->fetch()) {
		push (@fileFormatsComplete, $fileFormatName);
	}
	$sth->finish();
	foreach my $thisFileFormat (@fileFormatsComplete) {
		my $subData = '';
		my $sqlbitrate = "select round(tracks.bitrate/16000)*16, count(distinct tracks.id) as nooftracks from tracks";
		my $selectedVL = $prefs->get('selectedvirtuallibrary');
		if ($selectedVL && $selectedVL ne '') {
			$sqlbitrate .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
		}
		if (defined($genreFilter) && $genreFilter ne '') {
			$sqlbitrate .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
		}
		$sqlbitrate .= " where
			tracks.audio = 1
			and tracks.remote = 0
			and tracks.content_type=\"$thisFileFormat\"
			and tracks.bitrate is not null
			and tracks.bitrate > 0";
		my $decadeFilterVal = $prefs->get('decadefilterval');
		if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
			$sqlbitrate .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
		}
		$sqlbitrate .= " group by (case
			when round(tracks.bitrate/16000)*16 > 1400 then round(tracks.bitrate/160000)*160
			when round(tracks.bitrate/16000)*16 < 10 then 16
			else round(tracks.bitrate/16000)*16
			end)
		order by tracks.bitrate asc;";
		my $sth = $dbh->prepare($sqlbitrate);
		#eval {
			$sth->execute();
			my $xAxisDataItem;
			my $yAxisDataItem;
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				if ($subData eq '') {
					$subData = '"'.$xAxisDataItem.'": '.$yAxisDataItem;
				} else {
					$subData = $subData.', "'.$xAxisDataItem.'": '.$yAxisDataItem;
				}
				push (@bitRates, $xAxisDataItem) unless grep{$_ eq $xAxisDataItem} @bitRates;
			}
			$sth->finish();
			$subData = '{'.$subData.'}';
			push(@result, $subData);
		#};
	}
	my @sortedbitRates = sort { $a <=> $b } @bitRates;

	my @wrapper = (\@result, \@sortedbitRates, \@fileFormatsComplete);
	$log->debug('wrapper = '.Dumper(\@wrapper));

	return \@wrapper;
}

sub getDataTracksByFileSize {
	my $sqlstatement = "select cast(round(filesize/1048576) as int), count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			tracks.audio = 1
			and tracks.filesize is not null
			and tracks.filesize > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by (case
			when round(filesize/1048576) < 1 then 1
			when round(filesize/1048576) > 1000 then 1000
			else round(filesize/1048576)
			end)
		order by tracks.filesize asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByFileSizeAudioFileFormat {
	my $dbh = getCurrentDBH();
	my @result = ();
	my @fileFormats = ();
	my $genreFilter = $prefs->get('genrefilterid');

	# get track count for file sizes <= 100 MB
	foreach my $fileSize (1..100) {
		my $xLabelName = $fileSize;
		my $subData = '';
		my $sqlfilesize = "select tracks.content_type, count(distinct tracks.id) as nooftracks from tracks";
		my $selectedVL = $prefs->get('selectedvirtuallibrary');
		if ($selectedVL && $selectedVL ne '') {
			$sqlfilesize .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
		}
		if (defined($genreFilter) && $genreFilter ne '') {
			$sqlfilesize .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
		}
		$sqlfilesize .= " where
				tracks.audio = 1
				and tracks.filesize is not null
				and tracks.filesize > 0
				and
					case
						when $fileSize == 1 then round(tracks.filesize/1048576) <= $fileSize
						else round(tracks.filesize/1048576) == $fileSize
					end";
		my $decadeFilterVal = $prefs->get('decadefilterval');
		if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
			$sqlfilesize .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
		}
		$sqlfilesize .= " group by tracks.content_type
			order by tracks.content_type asc";
		my $sth = $dbh->prepare($sqlfilesize);
		#eval {
			$sth->execute();
			my $xAxisDataItem; # string values
			my $yAxisDataItem; # numeric values
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem);
				$subData = $subData.', "'.$xAxisDataItem.'": '.$yAxisDataItem;
				push(@fileFormats, $xAxisDataItem) unless grep{$_ eq $xAxisDataItem} @fileFormats;
			}
			$sth->finish();
			$subData = '{"x": '.'"'.$xLabelName.'"'.$subData.'}';
			push(@result, $subData);
		#};
	}

	# aggregate for files > 100 MB
		my $xLabelName = ' > 100';
		my $subData = '';
		my $sqlfilesize = "select tracks.content_type, count(distinct tracks.id) as nooftracks from tracks";
		my $selectedVL = $prefs->get('selectedvirtuallibrary');
		if ($selectedVL && $selectedVL ne '') {
			$sqlfilesize .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
		}
		if (defined($genreFilter) && $genreFilter ne '') {
			$sqlfilesize .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
		}
		$sqlfilesize .= " where
				tracks.audio = 1
				and tracks.filesize is not null
				and tracks.filesize > 0
				and round(tracks.filesize/1048576) > 100";
		my $decadeFilterVal = $prefs->get('decadefilterval');
		if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
			$sqlfilesize .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
		}
		$sqlfilesize .= " group by tracks.content_type
			order by tracks.content_type asc";
		my $sth = $dbh->prepare($sqlfilesize);
		#eval {
			$sth->execute();
			my $xAxisDataItem; # string values
			my $yAxisDataItem; # numeric values
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem);
				$subData = $subData.', "'.$xAxisDataItem.'": '.$yAxisDataItem;
				push(@fileFormats, $xAxisDataItem) unless grep{$_ eq $xAxisDataItem} @fileFormats;
			}
			$sth->finish();
			$subData = '{"x": '.'"'.$xLabelName.'"'.$subData.'}';
			push(@result, $subData);
		#};
	my @wrapper = (\@result, \@fileFormats);
	$log->debug('wrapper = '.Dumper(\@wrapper));

	return \@wrapper;
}

sub getDataTracksByGenre {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by nooftracks desc, genres.name asc
		limit ($rowLimit-1);";
	my $sqlResult = executeSQLstatement($sqlstatement);

	my $sum = 0;
	foreach my $hash ( @{$sqlResult} ) {
		$sum += $hash->{'yAxis'};
	}

	my $trackCountSQL = "select count(distinct tracks.id) from tracks";
	if ($selectedVL && $selectedVL ne '') {
		$trackCountSQL .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$trackCountSQL .= " where tracks.audio = 1";
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$trackCountSQL .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$trackCountSQL .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $trackCount = quickSQLcount($trackCountSQL);
	my $othersCount = $trackCount - $sum;
	push @{$sqlResult}, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_OTHERS'), 'yAxis' => $othersCount} unless ($othersCount == 0);
	return $sqlResult;
}

sub getDataTracksMostPlayed {
	my $sqlstatement = "select tracks.title, ifnull(tracks_persistent.playCount, 0), contributors.name from tracks
		join contributors on
			contributors.id = tracks.primary_artist
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " order by tracks_persistent.playCount desc, tracks.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataTracksMostPlayedAPC {
	my $sqlstatement = "select tracks.title, ifnull(alternativeplaycount.playCount, 0), contributors.name from tracks
		join contributors on
			contributors.id = tracks.primary_artist
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " order by alternativeplaycount.playCount desc, tracks.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataTracksMostSkippedAPC {
	my $sqlstatement = "select tracks.title, ifnull(alternativeplaycount.skipCount, 0), contributors.name from tracks
		join contributors on
			contributors.id = tracks.primary_artist
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " order by alternativeplaycount.skipCount desc, tracks.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataTracksByYear {
	my $sqlstatement = "select case when ifnull(tracks.year, 0) > 0 then tracks.year else 'Unknown' end, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by tracks.year asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByDateAdded {
	my $sqlstatement = "select strftime('%d-%m-%Y',tracks_persistent.added, 'unixepoch', 'localtime') as dateadded, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks_persistent.added > 0
			and tracks_persistent.added is not null
		group by strftime('%d-%m-%Y',tracks_persistent.added, 'unixepoch', 'localtime')
		order by strftime ('%Y',tracks_persistent.added, 'unixepoch', 'localtime') asc, strftime('%m',tracks_persistent.added, 'unixepoch', 'localtime') asc, strftime('%d',tracks_persistent.added, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTracksByDateLastModified {
	my $sqlstatement = "select case when ifnull(tracks.timestamp, 0) < 315532800 then 'Unkown' else strftime('%d-%m-%Y',tracks.timestamp, 'unixepoch', 'localtime') end, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " where
			tracks.timestamp > 0
			and tracks.timestamp is not null
		group by strftime('%d-%m-%Y',tracks.timestamp, 'unixepoch', 'localtime')
		order by strftime ('%Y',tracks.timestamp, 'unixepoch', 'localtime') asc, strftime('%m',tracks.timestamp, 'unixepoch', 'localtime') asc, strftime('%d',tracks.timestamp, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

# ---- artists ---- #

sub getDataArtistWithMostTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks from contributors
		join contributor_track on
			contributor_track.contributor = contributors.id and contributor_track.role in (1,5,6)
		join tracks on
			tracks.id = contributor_track.track";
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " where
			contributors.id is not null";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and contributors.name is not '$VAstring'
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by contributors.name
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistWithMostAlbums {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct albums.id) as noofalbums from albums
		join tracks on
			tracks.album = albums.id
		join contributors on
			contributors.id = albums.contributor
		join contributor_track on
			contributor_track.contributor = albums.contributor and contributor_track.role in (1,5)";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			ifnull(albums.compilation, 0) is not 1
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by contributors.name
		order by noofalbums desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistWithMostRatedTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
			and tracks_persistent.rating > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsHighestPercentageRatedTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
			having count(distinct tracks.id) >= $minArtistTracks
		order by ratedpercentage desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithTopRatedTracksRated {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
			having count(distinct tracks.id) >= $minArtistTracks
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostPlayedTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
			and tracks_persistent.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostPlayedTracksAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks from tracks
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
			and alternativeplaycount.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithTracksCompletelyPartlyNonePlayed {
	my @result = ();
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';

	my $sqlstatement_shared = "select count (distinct playedtracks.artistname) from (select distinct contributors.name as artistname, cast(count(distinct case when ifnull(tracks_persistent.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement_shared .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement_shared .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement_shared .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement_shared .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}

	my $sql_completelyplayed = $sqlstatement_shared . " group by tracks.primary_artist
			having playedpercentage == 100) as playedtracks";
	my $sql_partiallyplayed = $sqlstatement_shared . " group by tracks.primary_artist
			having playedpercentage > 0 and playedpercentage < 100) as playedtracks";
	my $sql_notplayed = $sqlstatement_shared . " group by tracks.primary_artist
			having playedpercentage == 0) as playedtracks";

	my $artistcount_completelyplayed = quickSQLcount($sql_completelyplayed);
	my $artistcount_partiallyplayed = quickSQLcount($sql_partiallyplayed);
	my $artistcount_notplayed = quickSQLcount($sql_notplayed);

	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_COMPLETELY'), 'yAxis' => $artistcount_completelyplayed}) unless ($artistcount_completelyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_PARTIALLY'), 'yAxis' => $artistcount_partiallyplayed}) unless ($artistcount_partiallyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_NOTPLAYED'), 'yAxis' => $artistcount_notplayed}) unless ($artistcount_notplayed == 0);

	return \@result;
}

sub getDataArtistsWithTracksCompletelyPartlyNonePlayedAPC {
	my @result = ();
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';

	my $sqlstatement_shared = "select count (distinct playedtracks.artistname) from (select distinct contributors.name as artistname, cast(count(distinct case when ifnull(alternativeplaycount.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement_shared .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement_shared .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement_shared .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement_shared .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}

	my $sql_completelyplayed = $sqlstatement_shared . " group by tracks.primary_artist
			having playedpercentage == 100) as playedtracks";
	my $sql_partiallyplayed = $sqlstatement_shared . " group by tracks.primary_artist
			having playedpercentage > 0 and playedpercentage < 100) as playedtracks";
	my $sql_notplayed = $sqlstatement_shared . " group by tracks.primary_artist
			having playedpercentage == 0) as playedtracks";

	my $artistcount_completelyplayed = quickSQLcount($sql_completelyplayed);
	my $artistcount_partiallyplayed = quickSQLcount($sql_partiallyplayed);
	my $artistcount_notplayed = quickSQLcount($sql_notplayed);

	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_COMPLETELY'), 'yAxis' => $artistcount_completelyplayed}) unless ($artistcount_completelyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_PARTIALLY'), 'yAxis' => $artistcount_partiallyplayed}) unless ($artistcount_partiallyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ARTISTS_PLAYED_NOTPLAYED'), 'yAxis' => $artistcount_notplayed}) unless ($artistcount_notplayed == 0);

	return \@result;
}

sub getDataArtistsHighestPercentagePlayedTracks {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, cast(count(distinct case when ifnull(tracks_persistent.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
			having count(distinct tracks.id) >= $minArtistTracks and playedpercentage < 100
		order by playedpercentage desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsHighestPercentagePlayedTracksAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, cast(count(distinct case when ifnull(alternativeplaycount.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
			having count(distinct tracks.id) >= $minArtistTracks and playedpercentage < 100
		order by playedpercentage desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostPlayedTracksAverage {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
		order by avgplaycount desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostPlayedTracksAverageAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(alternativeplaycount.playCount,0)) as avgplaycount from tracks
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
		order by avgplaycount desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostSkippedTracksAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, count(distinct tracks.id) as nooftracks from tracks
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'
			and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
		order by nooftracks desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsHighestPercentageSkippedTracksAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $minArtistTracks = $prefs->get('minartisttracks');
	my $sqlstatement = "select distinct contributors.name, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage from tracks
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
			having count(distinct tracks.id) >= $minArtistTracks
		order by skippedpercentage desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsWithMostSkippedTracksAverageAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select distinct contributors.name, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount from tracks
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist
		order by avgskipcount desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataArtistsRatingPlaycount {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select t.* from (select avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating, contributors.name from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist) as t
		where (t.avgplaycount >= 0.05 and t.avgrating >= 0.05);";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataArtistsRatingPlaycountAPC {
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';
	my $sqlstatement = "select t.* from (select avg(ifnull(alternativeplaycount.playCount,0)) as avgplaycount, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating, contributors.name from tracks
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and contributors.name is not '$VAstring'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.primary_artist) as t
		where (t.avgplaycount >= 0.05 and t.avgrating >= 0.05);";
	return executeSQLstatement($sqlstatement, 3);
}

# ---- albums ---- #

sub getDataAlbumsByYear {
	my $sqlstatement = "select case when albums.year > 0 then albums.year else 'Unknown' end, count(distinct albums.id) as noofalbums from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			(tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.year
		order by albums.year asc";
	return executeSQLstatement($sqlstatement);
}

sub getDataAlbumsWithMostTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostRatedTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsHighestPercentageRatedTracks {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct albums.title, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
			having count(distinct tracks.id) >= $minAlbumTracks
		order by ratedpercentage desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithTopRatedTracksRated {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select albums.title, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
			having count(distinct tracks.id) >= $minAlbumTracks
		order by avgrating desc, contributors.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostPlayedTracks {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostPlayedTracksAPC {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if ($genreFilter && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithTracksCompletelyPartlyNonePlayed {
	my @result = ();
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';

	my $sqlstatement_shared = "select count (distinct playedtracks.albumtitle) from (select distinct albums.title as albumtitle, cast(count(distinct case when ifnull(tracks_persistent.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from albums
		join tracks on
			tracks.album = albums.id
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement_shared .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement_shared .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement_shared .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement_shared .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}

	my $sql_completelyplayed = $sqlstatement_shared . " group by albums.title
			having playedpercentage == 100) as playedtracks";
	my $sql_partiallyplayed = $sqlstatement_shared . " group by albums.title
			having playedpercentage > 0 and playedpercentage < 100) as playedtracks";
	my $sql_notplayed = $sqlstatement_shared . " group by albums.title
			having playedpercentage == 0) as playedtracks";

	my $albumcount_completelyplayed = quickSQLcount($sql_completelyplayed);
	my $albumcount_partiallyplayed = quickSQLcount($sql_partiallyplayed);
	my $albumcount_notplayed = quickSQLcount($sql_notplayed);

	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_COMPLETELY'), 'yAxis' => $albumcount_completelyplayed}) unless ($albumcount_completelyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_PARTIALLY'), 'yAxis' => $albumcount_partiallyplayed}) unless ($albumcount_partiallyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_NOTPLAYED'), 'yAxis' => $albumcount_notplayed}) unless ($albumcount_notplayed == 0);

	return \@result;
}

sub getDataAlbumsWithTracksCompletelyPartlyNonePlayedAPC {
	my @result = ();
	my $VAstring = $serverPrefs->get('variousArtistsString') || 'Various Artists';

	my $sqlstatement_shared = "select count (distinct playedtracks.albumtitle) from (select distinct albums.title as albumtitle, cast(count(distinct case when ifnull(alternativeplaycount.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from albums
		join tracks on
			tracks.album = albums.id
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join contributors on
			contributors.id = tracks.primary_artist";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement_shared .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement_shared .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement_shared .= " where
			(tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement_shared .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}

	my $sql_completelyplayed = $sqlstatement_shared . " group by albums.title
			having playedpercentage == 100) as playedtracks";
	my $sql_partiallyplayed = $sqlstatement_shared . " group by albums.title
			having playedpercentage > 0 and playedpercentage < 100) as playedtracks";
	my $sql_notplayed = $sqlstatement_shared . " group by albums.title
			having playedpercentage == 0) as playedtracks";

	my $albumcount_completelyplayed = quickSQLcount($sql_completelyplayed);
	my $albumcount_partiallyplayed = quickSQLcount($sql_partiallyplayed);
	my $albumcount_notplayed = quickSQLcount($sql_notplayed);

	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_COMPLETELY'), 'yAxis' => $albumcount_completelyplayed}) unless ($albumcount_completelyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_PARTIALLY'), 'yAxis' => $albumcount_partiallyplayed}) unless ($albumcount_partiallyplayed == 0);
	push (@result, {'xAxis' => string('PLUGIN_VISUALSTATISTICS_CHARTLABEL_ALBUMS_PLAYED_NOTPLAYED'), 'yAxis' => $albumcount_notplayed}) unless ($albumcount_notplayed == 0);

	return \@result;
}

sub getDataAlbumsHighestPercentagePlayedTracks {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct albums.title, cast(count(distinct case when ifnull(tracks_persistent.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
			having count(distinct tracks.id) >= $minAlbumTracks and playedpercentage < 100
		order by playedpercentage desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsHighestPercentagePlayedTracksAPC {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct albums.title, cast(count(distinct case when ifnull(alternativeplaycount.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
			having count(distinct tracks.id) >= $minAlbumTracks and playedpercentage < 100
		order by playedpercentage desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostPlayedTracksAverage {
	my $sqlstatement = "select albums.title, avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
		order by avgplaycount desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostPlayedTracksAverageAPC {
	my $sqlstatement = "select albums.title, avg(ifnull(alternativeplaycount.playCount,0)) as avgplaycount, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
		order by avgplaycount desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostSkippedTracksAPC {
	my $sqlstatement = "select albums.title, count(distinct tracks.id) as nooftracks, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by albums.title
		order by nooftracks desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsHighestPercentageSkippedTracksAPC {
	my $minAlbumTracks = $prefs->get('minalbumtracks');
	my $sqlstatement = "select distinct albums.title, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
			having count(distinct tracks.id) >= $minAlbumTracks
		order by skippedpercentage desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

sub getDataAlbumsWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select albums.title, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount, contributors.name from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " join contributors on
			contributors.id = albums.contributor
		left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			albums.title is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by albums.title
		order by avgskipcount desc, albums.title asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement, 3);
}

# ---- genres ---- #

sub getDataGenresWithMostTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostAlbums {
	my $sqlstatement = "select genres.name, count(distinct albums.id) as noofalbums from albums
		join tracks on
			tracks.album = albums.id";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(albums.year, 0) >= $decadeFilterVal and ifnull(albums.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by noofalbums desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostRatedTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresHighestPercentageRatedTracks {
	my $sqlstatement = "select genres.name, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by ratedpercentage desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithTopRatedTracksRated {
	my $sqlstatement = "select genres.name, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by avgrating desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostPlayedTracks {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostPlayedTracksAPC {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.playCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresHighestPercentagePlayedTracks {
	my $sqlstatement = "select genres.name, cast(count(distinct case when ifnull(tracks_persistent.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by playedpercentage desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresHighestPercentagePlayedTracksAPC {
	my $sqlstatement = "select genres.name, cast(count(distinct case when ifnull(alternativeplaycount.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by playedpercentage desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostPlayedTracksAverage {
	my $sqlstatement = "select genres.name, avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by avgplaycount desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostPlayedTracksAverageAPC {
	my $sqlstatement = "select genres.name, avg(ifnull(alternativeplaycount.playCount,0)) as avgplaycount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by avgplaycount desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostSkippedTracksAPC {
	my $sqlstatement = "select genres.name, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.skipCount > 0";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by genres.name
		order by nooftracks desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresHighestPercentageSkippedTracksAPC {
	my $sqlstatement = "select genres.name, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by skippedpercentage desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select genres.name, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		join genre_track on
			genre_track.track = tracks.id
		join genres on
			genres.id = genre_track.genre
		where
			genres.name is not null
			and (tracks.audio = 1 or tracks.extid is not null)";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by avgskipcount desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataGenresWithTopAverageBitrate {
	my $sqlstatement = "select genres.name, avg(round(ifnull(tracks.bitrate,0)/16000)*16) as avgbitrate from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	$sqlstatement .= " join genre_track on
			tracks.id=genre_track.track
		join genres on
			genre_track.genre=genres.id
		where
			genres.name is not null
			and tracks.audio = 1";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by genres.name
		order by avgbitrate desc, genres.name asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

# ---- years ---- #

sub getDataYearsWithMostTracks {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by nooftracks desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostAlbums {
	my $sqlstatement = "select year, count(distinct tracks.album) as noofalbums from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			tracks.year > 0
			and tracks.year is not null
			and tracks.album is not null
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and (tracks.audio = 1 or tracks.extid is not null)
		group by year
		order by noofalbums desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostRatedTracks {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0
		group by tracks.year
		order by nooftracks desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsHighestPercentageRatedTracks {
	my $sqlstatement = "select tracks.year, cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by ratedpercentage desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithTopRatedTracksRated {
	my $sqlstatement = "select tracks.year, avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by avgrating desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostPlayedTracks {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by tracks.year
		order by nooftracks desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsHighestPercentagePlayedTracks {
	my $sqlstatement = "select tracks.year, cast(count(distinct case when ifnull(tracks_persistent.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by playedpercentage desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsHighestPercentagePlayedTracksAPC {
	my $sqlstatement = "select tracks.year, cast(count(distinct case when ifnull(alternativeplaycount.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by playedpercentage desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostPlayedTracksAPC {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.playCount > 0
		group by tracks.year
		order by nooftracks desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostPlayedTracksAverage {
	my $sqlstatement = "select year, avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by avgplaycount desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostPlayedTracksAverageAPC {
	my $sqlstatement = "select year, avg(ifnull(alternativeplaycount.playCount,0)) as avgplaycount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by avgplaycount desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostSkippedTracksAPC {
	my $sqlstatement = "select tracks.year, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.skipCount > 0
		group by tracks.year
		order by nooftracks desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsHighestPercentageSkippedTracksAPC {
	my $sqlstatement = "select tracks.year, cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by skippedpercentage desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataYearsWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select year, avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by tracks.year
		order by avgskipcount desc, tracks.year asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

# ---- decades ---- #

sub getDataDecadesWithMostTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostAlbums {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.album) as noofalbums from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			tracks.year > 0
			and tracks.year is not null
			and tracks.album is not null
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and (tracks.audio = 1 or tracks.extid is not null)
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by noofalbums desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostRatedTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.rating > 0
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesHighestPercentageRatedTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', cast(count(distinct case when ifnull(tracks_persistent.rating, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as ratedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by ratedpercentage desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithTopRatedTracksRated {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', avg(ifnull(tracks_persistent.rating,0)/20) as avgrating from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by avgrating desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and tracks_persistent.playCount > 0
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracksAPC {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.playCount > 0
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesHighestPercentagePlayedTracks {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', cast(count(distinct case when ifnull(tracks_persistent.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by playedpercentage desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesHighestPercentagePlayedTracksAPC {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', cast(count(distinct case when ifnull(alternativeplaycount.playCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as playedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by playedpercentage desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracksAverage {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', avg(ifnull(tracks_persistent.playCount,0)) as avgplaycount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by avgplaycount desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostPlayedTracksAverageAPC {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', avg(ifnull(alternativeplaycount.playCount,0)) as avgplaycount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by avgplaycount desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostSkippedTracksAPC {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
			and alternativeplaycount.skipCount > 0
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by nooftracks desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesHighestPercentageSkippedTracksAPC {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', cast(count(distinct case when ifnull(alternativeplaycount.skipCount, 0) > 0 then tracks.id else null end) as float) / cast (count(distinct tracks.id) as float) * 100 as skippedpercentage from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by skippedpercentage desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

sub getDataDecadesWithMostSkippedTracksAverageAPC {
	my $sqlstatement = "select cast(((tracks.year/10)*10) as int)||'s', avg(ifnull(alternativeplaycount.skipCount,0)) as avgskipcount from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join alternativeplaycount on
			alternativeplaycount.urlmd5 = tracks.urlmd5
		where
			tracks.year > 0
			and tracks.year is not null
			and (tracks.audio = 1 or tracks.extid is not null)
			and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir'
		group by cast(((tracks.year/10)*10) as int)||'s'
		order by avgskipcount desc, cast(((tracks.year/10)*10) as int)||'s' asc
		limit $rowLimit;";
	return executeSQLstatement($sqlstatement);
}

# ---- misc. ---- #

sub getDataListeningTimes {
	my $sqlstatement = "select strftime('%H:%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') as timelastplayed, count(distinct tracks.id) as nooftracks from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " left join tracks_persistent on
			tracks_persistent.urlmd5 = tracks.urlmd5
		where
			tracks_persistent.lastPlayed > 0
			and tracks_persistent.lastPlayed is not null
		group by strftime('%H:%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime')
		order by strftime ('%H',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') asc, strftime('%M',tracks_persistent.lastPlayed, 'unixepoch', 'localtime') asc;";
	return executeSQLstatement($sqlstatement);
}

sub getDataTrackTitleMostFrequentWords {
	my $dbh = getCurrentDBH();
	my $sqlstatement = "select tracks.titlesearch from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			length(tracks.titlesearch) > 2
			and tracks.audio = 1";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.titlesearch";
	my $thisTitle;
	my %frequentwords;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute();
	$sth->bind_columns(undef, \$thisTitle);
	while ($sth->fetch()) {
		next unless $thisTitle;
		my @words = split /\W+/, $thisTitle; #skip non-word characters
		foreach my $word(@words){
			chomp $word;
			$word = lc $word;
			$word =~ s/^\s+|\s+$//g; #remove beginning/trailing whitespace
			if ((length $word < 3) || $ignoreCommonWords{$word}) {next;}
			$frequentwords{$word} ||= 0;
			$frequentwords{$word}++;
		}
	}

	my @keys = ();
	foreach my $word (sort { $frequentwords{$b} <=> $frequentwords{$a} or "\F$a" cmp "\F$b"} keys %frequentwords) {
		push (@keys, {'xAxis' => $word, 'yAxis' => $frequentwords{$word}}) unless ($frequentwords{$word} == 0);
		last if scalar @keys >= 50;
	};

	$log->debug(Dumper(\@keys));
	return \@keys;
}

sub getDataTrackLyricsMostFrequentWords {
	my $dbh = getCurrentDBH();
	my $sqlstatement = "select tracks.lyrics from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sqlstatement .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sqlstatement .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sqlstatement .= " where
			length(tracks.lyrics) > 15
			and tracks.audio = 1";
	my $decadeFilterVal = $prefs->get('decadefilterval');
	if (defined($decadeFilterVal) && $decadeFilterVal ne '') {
		$sqlstatement .= " and ifnull(tracks.year, 0) >= $decadeFilterVal and ifnull(tracks.year, 0) < ($decadeFilterVal + 10)";
	}
	$sqlstatement .= " group by tracks.titlesearch";
	my $lyrics;
	my %frequentwords;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute();
	$sth->bind_columns(undef, \$lyrics);
	while ($sth->fetch()) {
		next unless $lyrics;
		my @words = split /\W+/, $lyrics; #skip non-word characters
		foreach my $word(@words){
			chomp $word;
			$word = lc $word;
			$word =~ s/^\s+|\s+$//g; #remove beginning/trailing whitespace
			if ((length $word < 3) || $ignoreCommonWords{$word}) {next;}
			$frequentwords{$word} ||= 0;
			$frequentwords{$word}++;
		}
	}
	my @keys = ();
	foreach my $word (sort { $frequentwords{$b} <=> $frequentwords{$a} or "\F$a" cmp "\F$b"} keys %frequentwords) {
		push (@keys, {'xAxis' => $word, 'yAxis' => $frequentwords{$word}}) unless ($frequentwords{$word} == 0);
		last if scalar @keys >= 50;
	};

	$log->debug(Dumper(\@keys));
	return \@keys;
}

#####################
# helpers

sub executeSQLstatement {
	my @result = ();
	my $dbh = getCurrentDBH();
	my $sqlstatement = shift;
	my $numberValuesToBind = shift || 2;
	#eval {
		my $sth = $dbh->prepare($sqlstatement);
		$sth->execute() or do {
			$sqlstatement = undef;
		};
		my $xAxisDataItem; # string values
		my $yAxisDataItem; # numeric values
		if ($numberValuesToBind == 3) {
			my $labelExtraDataItem; # extra data for chart labels
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem, \$labelExtraDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem); utf8::decode($labelExtraDataItem);
				push (@result, {'xAxis' => $xAxisDataItem, 'yAxis' => $yAxisDataItem, 'labelExtra' => $labelExtraDataItem}) unless ($yAxisDataItem == 0);
			}
		} else {
			$sth->bind_columns(undef, \$xAxisDataItem, \$yAxisDataItem);
			while ($sth->fetch()) {
				utf8::decode($xAxisDataItem);
				push (@result, {'xAxis' => $xAxisDataItem, 'yAxis' => $yAxisDataItem}) unless ($yAxisDataItem == 0);
			}
		}
		$sth->finish();
	#};
	$log->debug('SQL result = '.Dumper(\@result));
	$log->debug('Got '.scalar(@result).' items');
	return \@result;
}

sub quickSQLcount {
	my $dbh = getCurrentDBH();
	my $sqlstatement = shift;
	my $thisCount;
	my $sth = $dbh->prepare($sqlstatement);
	$sth->execute();
	$sth->bind_columns(undef, \$thisCount);
	$sth->fetch();
	return $thisCount;
}

sub getVirtualLibraries {
	my (@items, @hiddenVLs);
	my $libraries = Slim::Music::VirtualLibraries->getLibraries();
	$log->debug('ALL virtual libraries: '.Dumper($libraries));

	while (my ($k, $v) = each %{$libraries}) {
		my $count = Slim::Utils::Misc::delimitThousands(Slim::Music::VirtualLibraries->getTrackCount($k)) + 0;
		my $name = Slim::Music::VirtualLibraries->getNameForId($k);
		$log->debug("VL: ".$name." (".$count.")");

		push @items, {
			'name' => Slim::Utils::Unicode::utf8decode($name, 'utf8')." (".$count.($count == 1 ? " ".string("PLUGIN_VISUALSTATISTICS_CHARTLABEL_UNIT_TRACK").")" : " ".string("PLUGIN_VISUALSTATISTICS_CHARTLABEL_UNIT_TRACKS").")"),
			'sortName' => Slim::Utils::Unicode::utf8decode($name, 'utf8'),
			'library_id' => $k,
		};
	}
	push @items, {
		'name' => string("PLUGIN_VISUALSTATISTICS_VL_COMPLETELIB_NAME"),
		'sortName' => " Complete Library",
		'library_id' => undef,
	};
	@items = sort { $a->{'sortName'} cmp $b->{'sortName'} } @items;
	return \@items;
}

sub getGenres {
	my @genres = ();
	my $query = ['genres', 0, 999_999];
	my $request;

	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	push @{$query}, 'library_id:'.$selectedVL if ($selectedVL && $selectedVL ne '');
	$request = Slim::Control::Request::executeRequest(undef, $query);

	foreach my $genre ( @{ $request->getResult('genres_loop') || [] } ) {
		push (@genres, {'name' => $genre->{'genre'}, 'id' => $genre->{'id'}});
	}
	push @genres, {
		'name' => string("PLUGIN_VISUALSTATISTICS_GENREFILTER_ALLGENRES"),
		'id' => undef,
	};
	@genres = sort { lc($a->{'name'}) cmp lc($b->{'name'}) } @genres;
	$log->debug('genres list = '.Dumper(\@genres));
	return \@genres;
}

sub getDecades {
	my $dbh = getCurrentDBH();
	my @decades = ();
	my $decadesQueryResult = {};
	my $unknownString = string('PLUGIN_DYNAMICPLAYLISTS3_LANGSTRINGS_UNKNOWN');

	my $sql_decades = "select cast(((ifnull(tracks.year,0)/10)*10) as int) as decade,case when tracks.year>0 then cast(((tracks.year/10)*10) as int)||'s' else '$unknownString' end as decadedisplayed from tracks";
	my $selectedVL = $prefs->get('selectedvirtuallibrary');
	if ($selectedVL && $selectedVL ne '') {
		$sql_decades .= " join library_track on library_track.track = tracks.id and library_track.library = '$selectedVL'"
	}
	my $genreFilter = $prefs->get('genrefilterid');
	if (defined($genreFilter) && $genreFilter ne '') {
		$sql_decades .= " join genre_track on genre_track.track = tracks.id and genre_track.genre == $genreFilter";
	}
	$sql_decades .= " where tracks.audio = 1 group by decade order by decade desc";

	my ($decade, $decadeDisplayName);
	eval {
		my $sth = $dbh->prepare($sql_decades);
		$sth->execute() or do {
			$sql_decades = undef;
		};
		$sth->bind_columns(undef, \$decade, \$decadeDisplayName);

		while ($sth->fetch()) {
			push (@decades, {'name' => $decadeDisplayName, 'val' => $decade});
		}
		$sth->finish();
		$log->debug('decadesQueryResult = '.Dumper($decadesQueryResult));
	};
	if ($@) {
		$log->warn("Database error: $DBI::errstr\n$@");
		return 'error';
	}
	unshift @decades, {
		'name' => string("PLUGIN_VISUALSTATISTICS_GENREFILTER_ALLDECADES"),
		'val' => undef,
	};
	$log->debug('decade list = '.Dumper(\@decades));
	return \@decades;
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

sub prettifyTime {
	my $timeinseconds = shift;
	my $seconds = (int($timeinseconds)) % 60;
	my $minutes = (int($timeinseconds / (60))) % 60;
	my $hours = (int($timeinseconds / (60*60))) % 24;
	my $days = (int($timeinseconds / (60*60*24))) % 7;
	my $weeks = (int($timeinseconds / (60*60*24*7))) % 52;
	my $years = (int($timeinseconds / (60*60*24*365))) % 10;
	my $prettyTime = (($years > 0 ? $years.($years == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEYEAR").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEYEARS").'  ') : '').($weeks > 0 ? $weeks.($weeks == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEWEEK").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEWEEKS").'  ') : '').($days > 0 ? $days.($days == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEDAY").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEDAYS").'  ') : '').($hours > 0 ? $hours.($hours == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEHOUR").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEHOURS").'  ') : '').($minutes > 0 ? $minutes.($minutes == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEMIN").'  ' : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMEMINS").'  ') : '').($seconds > 0 ? $seconds.($seconds == 1 ? ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMESEC") : ' '.string("PLUGIN_VISUALSTATISTICS_MISCSTATS_TEXT_TIMESECS")) : ''));
	return $prettyTime;
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
