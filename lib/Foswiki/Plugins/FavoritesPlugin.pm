# See bottom of file for default license and copyright information

package Foswiki::Plugins::FavoritesPlugin;

use strict;
use warnings;

use Encode ();
use Error qw( :try );
use Foswiki::Func ();
use Foswiki::Meta ();
use Foswiki::Plugins ();

our $VERSION = '0.9.2';
our $RELEASE = '0.9.2';
our $SHORTDESCRIPTION = 'Allow users to bookmark topics/attachments within the wiki';
our $NO_PREFS_IN_TOPIC = 1;

sub initPlugin {
    my ($topic, $web, $user, $installWeb) = @_;

    if ($Foswiki::Plugins::VERSION < 2.0) {
        Foswiki::Func::writeWarning('Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm');
        return 0;
    }

    Foswiki::Meta::registerMETA('FAVORITE', many => 1, require => [ 'name', 'web', 'topic' ], allow => ['file']);
    Foswiki::Func::registerTagHandler('FAVORITEBUTTON', \&_FAVORITEBUTTON);
    Foswiki::Func::registerTagHandler('FAVORITELIST', \&_FAVORITELIST);
    Foswiki::Func::registerRESTHandler('update', \&_restUpdate,
        authenticate => 1,
        http_allow => 'GET,POST',
    );

    return 1;
}

sub _userTopic {
    my $session = $Foswiki::Plugins::SESSION;
    my $user = shift || Foswiki::Func::getWikiName($session->{user});
    my $web = $Foswiki::cfg{UsersWebName};
    return undef unless Foswiki::Func::topicExists($web, $user);
    my ($meta) = Foswiki::Func::readTopic($web, $user);
    return $meta;

}

sub _saveTopic {
    my $meta = shift;
    $meta->saveAs($meta->web, $meta->topic, dontlog => 1, minor => 1);
}

sub _internalName {
    my ($web, $topic, $file) = @_;

    my ($tweb, $ttopic) = Foswiki::Func::normalizeWebTopicName($web, $topic);
    my $name = "$tweb.$ttopic";
    $name .= ":$file" if defined $file && $file ne '';
    return $name;
}

my $ifParser;

sub _FAVORITEBUTTON {
    my ($session, $params, $topic, $web, $meta) = @_;

    my $targetWeb = $params->{web};
    my $targetTopic = $params->{topic};
    $targetWeb = $web unless defined $targetWeb;
    $targetWeb =~ s!\.!/!g; # SolrPlugin compatibility
    $targetTopic = $topic unless defined $targetTopic;
    my $redirect = $params->{redirectto} || "$targetWeb.$targetTopic";
    my $file = $params->{file} || '';

    my $format = $params->{format} || '';
    return '' if !$format;

    # This code mostly lifted from Foswiki::Macros::IF
    unless ($ifParser) {
        require Foswiki::If::Parser;
        $ifParser = new Foswiki::If::Parser();
    }
    my $cond = $params->{cond} || '';
    my $condresult = 1;
    if ($cond) {
        try {
            my $expr = $ifParser->parse($cond);
            $condresult = $expr->evaluate(tom => $meta, data => $meta);
        }
        catch Foswiki::Infix::Error with {
            my $e = shift;
            return $session->inlineAlert('alerts', 'generic', 'IF{',
                $params->stringify(), '}:', $e->{-text});
        };
    }
    return '' unless $condresult;

    my $name = _internalName($targetWeb, $targetTopic, $file);

    my $home = _userTopic();
    return '' unless defined $home;
    my $targetData = $home->get('FAVORITE', $name);
    my $mode = defined($targetData) ? 'active' : 'inactive';
    my $action = ($mode eq 'active') ? 'remove' : 'add';
    $format =~ s/\$([a-z_]+)/
        exists $params->{$mode."_$1"} ?
        	$params->{$mode."_$1"} :
            "\$$1"
    /egi;
    $format =~ s/\$web/$targetWeb/g;
    $format =~ s/\$topic/$targetTopic/g;
    $format =~ s/\$file/$file/g;
    $format =~ s/\$name/$name/g;
    $format =~ s[\$formstart][<literal><form method="post"
        action="%SCRIPTURLPATH{rest}%/FavoritesPlugin/update">
        <input type="hidden" name="topic" value="$targetWeb.$targetTopic" />
        <input type="hidden" name="action" value="$action" />
        <input type="hidden" name="redirect" value="$redirect" />
        <input type="hidden" name="file" value="$file" />
    ]g;
    $format =~ s/\$formend/<\/form><\/literal>/g;
    my $js = "jQuery(this).parents('form:first').submit();return false;";
    if (Foswiki::Func::getContext()->{SafeWikiSignable}) {
        Foswiki::Plugins::SafeWikiPlugin::Signatures::permitInlineCode($js);
    }
    $format =~ s!\$linkstart!<a href="#" onclick="$js">!g;
    $format =~ s!\$linkend!</a>!g;
    $format =~ s#\$url#%SCRIPTURLPATH{rest}%/FavoritesPlugin/update/$targetWeb/$targetTopic?action=$action;file=$file;redirect=$redirect#g;

    return $format;
}

sub _FAVORITELIST {
    my ($session, $params, $topic, $web, $meta) = @_;

    my $home = _userTopic();
    return '' unless defined $home;

    my $type = $params->{type} || 'topics';
    my $showTopics = ($type !~ /^files$/i);
    my $showFiles = ($type !~ /^topics$/i);

    my $format = $params->{format} || '   * [[$webtopic]]$n';
    my $sep = $params->{separator} || '';
    my $res = '';

    my $idx = 0;
    foreach my $fav ($home->find('FAVORITE')) {
        next if $fav->{file} && !$showFiles;
        next if !$fav->{file} && !$showTopics;
        next if !Foswiki::Func::checkAccessPermission('VIEW', $session->{user}, undef, $fav->{topic}, $fav->{web});

        $res .= $sep if $idx++;

        my $line = $format;
        my $sweb = $fav->{web}; $sweb =~ s#/#.#g;
        $line =~ s/\$n/\n/g;
        $line =~ s/\$webtopic/$fav->{web}.$fav->{topic}/g;
        $line =~ s/\$swebtopic/$sweb.$fav->{topic}/g;
        $line =~ s/\$web/$fav->{web}/g;
        $line =~ s/\$sweb/$sweb/g;
        $line =~ s/\$topic/$fav->{topic}/g;
        $line =~ s/\$file/$fav->{file}/g;
        $res .= $line;
    }
    return ($params->{default} || '') if $res eq '';
    return $res;
}

sub _outputREST {
    my ($response, $status, $text) = @_;
    unless (utf8::is_utf8($text)) {
        my $charset = $Foswiki::cfg{Site}{CharSet} || 'iso-8859-1';
        $text = Encode::decode($charset, $text, Encode::FB_HTMLCREF);
    }
    $text = Encode::encode_utf8($text);

    $response->header(
        -status  => $status,
        -type    => 'text/plain',
        -charset => 'UTF-8'
    );
    $response->print($text);

    print STDERR $text if $status >= 400;
    return;
}

sub _restUpdate {
    my ($session, $plugin, $verb, $response) = @_;
    my $req = $session->{request};
    my $action = $req->param('action');
    my $file = $req->param('file');
    my $redirect = $req->param('redirect');

    if ($action !~ /^(?:add|remove)$/) {
        return _outputREST($response, 400, "Invalid action supplied");
    }

    my $home = _userTopic();
    my $web = $session->{webName};
    my $topic = $session->{topicName};
    my $name = _internalName($web, $topic, $file);
    if ( $action eq 'add' ) {
        my $data = {
            name => $name,
            web => $web,
            topic => $topic,
        };
        $data->{file} = $file if defined $file;
        $home->putKeyed('FAVORITE', $data);
    } else {
        $home->remove('FAVORITE', $name);
    }
    _saveTopic($home);
    if ($redirect) {
        $redirect =~ s#\.#/#g;
        Foswiki::Func::redirectCgiQuery($req, $Foswiki::cfg{ScriptUrlPaths}{view} ."/$redirect");
        return;
    }
    _outputREST($response, 200, "{\"status\":\"ok\"}");
}

sub _moveFavoritesForUser {
    my ($userMeta, $moveInfo) = @_;

    while (my ($k, $v) = each(%$moveInfo)) {
        next unless $userMeta->get('FAVORITE', $k);
        $userMeta->remove('FAVORITE', $k);
        my $data = {
            name => _internalName(@$v),
            web => $v->[0],
            topic => $v->[1],
        };
        next if $data->{web} eq $Foswiki::cfg{TrashWebName}; # Simply don't re-create
        $data->{file} = $v->[2] if defined $v->[2];
        $userMeta->putKeyed('FAVORITE', $data);
    }
    _saveTopic($userMeta);
}

sub _collectTopicResources {
    my ($res, $oldWeb, $oldTopic, $newWeb, $newTopic) = @_;

    my ($meta) = Foswiki::Func::readTopic($newWeb, $newTopic);
    unless (defined $meta) {
        Foswiki::Func::writeWarning(
            "Unexpected error loading data for $newWeb.$newTopic (after rename)");
    }

    my $name = _internalName($oldWeb, $oldTopic);
    $res->{$name} = [$newWeb, $newTopic];
    foreach my $att ($meta->find('FILEATTACHMENT')) {
        $name = _internalName($oldWeb, $oldTopic, $att->{name});
        $res->{$name} = [$newWeb, $newTopic, $att->{name}];
    }
}

sub afterRenameHandler {
    my ($oldWeb, $oldTopic, $oldAttachment,
        $newWeb, $newTopic, $newAttachment) = @_;

    return if $oldWeb eq $Foswiki::cfg{TrashWebName};

    # special case: KVPPlugin's changeState handler does
    # magic things and should be left alone
    my $session = $Foswiki::Plugins::SESSION;
    my $req = $session->{request};
    if ($req->action eq 'rest') {
        my $pathInfo = $req->path_info;
        return if $pathInfo =~ m#^/KVPPlugin/changeState#;
    }

    # Step 1: collect all potentially necessary changes
    my $moveInfo = {};
    if (!$oldTopic) {
        # Moved an entire web
        foreach my $topic (Foswiki::Func::getTopicList($newWeb)) {
            _collectTopicResources($moveInfo, $oldWeb, $topic, $newWeb, $topic);
        }
    } elsif (!$oldAttachment) {
        # Moved a single topic
        # Ignore workflow-related moving
        if (exists $Foswiki::cfg{Extensions}{KVPPlugin}{suffix}) {
            my $suffix = $Foswiki::cfg{Extensions}{KVPPlugin}{suffix};
            return if ($oldTopic =~ /\Q$suffix\E$/ || $newTopic =~ /\Q$suffix\E$/);
        }
        _collectTopicResources($moveInfo, $oldWeb, $oldTopic, $newWeb, $newTopic);
    } else {
        # Moved a single attachment
        my $name = _internalName($oldWeb, $oldTopic, $oldAttachment);
        $moveInfo->{$name} = [$newWeb, $newTopic, $newAttachment];
    }

    # Step 2: apply to every user
    foreach my $user (Foswiki::Func::getTopicList($Foswiki::cfg{UsersWebName})) {
        my $home = _userTopic($user);
        next unless defined $home; # not found or not readable
        _moveFavoritesForUser($home, $moveInfo);
    }
}

1;
