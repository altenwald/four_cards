var ws;
var game_id;
var username;
var dealt = false;
var refresh_hand = false;
var refresh_shown = false;
var card;
var timer;
var deck_style = "napoletane"

function disconnected(should_i_reconnect) {
    if (should_i_reconnect) {
        $("#game-msg").html("<strong>¡Disconnected! Reconnecting...</strong>");
        setTimeout(function(){ connect(); }, 1000);
    } else {
        $("#game-msg").html("<strong>¡Disconnected!</strong>");
    }
}

function change_deck_style(from) {
    var to = deck_style;
    $("img").each(function (i, e) {
        var attr = $(e).attr("src");
        if (attr.startsWith("/img/cards/" + from)) {
            var pngfile = attr.split("/").reverse()[0];
            $(e).attr("src", "/img/cards/" + to + "/" + pngfile);
        }
    });
}

function send(message) {
    console.log("send: ", message);
    ws.send(JSON.stringify(message));
};

function connect() {
    const hostname = document.location.href.split("/", 3)[2];
    if (ws) {
        ws.close();
    }
    var schema = (location.href.split(":")[0] == "https") ? "wss" : "ws";
    ws = new WebSocket(schema + "://" + hostname + "/websession");
    ws.onopen = function(){
        var parts = new URL(document.URL);
        var uri = parts.pathname;
        console.log("connected!");
        switch (uri) {
            case "/":
                send({type: "create"});
                break;
            default:
                set_game_id(uri.slice(1));
        }
        // send({type: "deck", name: deck});
        if (!username) {
            $("#onBoardingModal").modal('show');
            $("#dealingModal").modal('hide');
        } else {
            clean_players();
            send({type: "join", name: game_id, username: username});
            $("#onBoardingModal").modal('hide');
            if (!dealt) {
                $("#dealingModal").modal('show');
                $("#bot-name").focus();
            } else {
                $("#dealingModal").modal('hide');
            }
        }
        $("#game-msg").html("");
        if (timer) {
            clearInterval(timer);
        }
        timer = setInterval(function(){
            send({type: "ping"});
        }, 10000);
    };
    ws.onerror = function(message){
        console.error("onerror", message);
        disconnected(false);
    };
    ws.onclose = function() {
        console.error("onclose");
        disconnected(true);
    }
    ws.onmessage = function(message){
        console.log("Got message", message.data);
        var data = JSON.parse(message.data);
        process_event_msg(data);
        switch(data.type) {
            case "join":
                update_player(data.username);
                break;
            case "leave":
                clear_player(data.username);
                break;
            case "id":
                set_game_id(data.id);
                $("#onBoardingModal").modal('show');
                break;
            case "vsn":
                $("#vsn").html("v" + data.vsn);
                break;
            case "dealt":
                start_game(data);
                break;
            case "update":
            case "turn":
                if (data.turn == username) {
                    update_game(data);
                } else {
                    update_hand(data.hand);
                    update_turn(data.turn);
                    update_captured(data.players, data.captured);
                    update_shown_card(data.shown);
                    update_playing_card(data.playing);
                }
                break;
            case "game_over":
                if (data.winner == username) {
                    $("#game-over-msg").html("You win!!!");
                } else {
                    $("#game-over-msg").html("You loose :'( ... " + data.winner + " won!");
                }
                update_shown_card(data.shown);
                update_turn(data.turn);
                update_captured(data.players, data.captured);
                update_playing_card(data.playing);
                $("#gameOverModal").modal('show');
                break;
            case "notfound":
                location.href = get_url_base();
                break;
        }
    };
}

function add_event_msg(msg, color) {
    if (!color) {
        $("#log").prepend("<li>" + msg + "</li>");
    } else {
        var class_name = "table-danger";
        switch (color) {
            case "green": class_name = "table-success"; break;
            case "blue": class_name = "table-info"; break;
            case "yellow": class_name = "table-danger"; break;
        }
        $("#log").prepend("<li class='" + class_name + "'>" + msg + "</li>");
    }
}

function process_event_msg(data) {
    switch (data.type) {
        case "dealt":
            if (!dealt) {
                add_event_msg("starts the game!");
            }
            break;
        case "pick_from_deck":
            add_event_msg("oh! " + data.turn + " had to pick one card from deck!");
            break;
        case "gameover":
            if (data.winner == username) {
                add_event_msg("you beat your opponents! well done!");
            } else {
                add_event_msg("well, best luck next time, " + data.winner + " wins!");
            }
            break;
        case "pass":
            if (data.previous == username) {
                add_event_msg("don't worry, you can! next time you could use your cards!");
            } else {
                if (data.turn == username) {
                    add_event_msg("you have an opportunity! " + data.previous + " passed!");
                } else {
                    add_event_msg("sadly " + data.previous + " couldn't use any card!");
                }
            }
            break;
        case "reverse":
            add_event_msg(data.previous + " reversed the turns! what a mess!");
            break;
    }
}

function start_game(data) {
    dealt = true;
    $("#onBoardingModal").modal('hide');
    $("#dealingModal").modal('hide');
    $("#gameOverModal").modal('hide');
    $("#log").html("");
    update_game(data);
}

function update_shown_card(shown) {
    var html = shown.reduce(function(acc, card) {
        return [acc[0] + 1, acc[1] + "<img src='" + card + "' id='card-" + acc[0] + "' class='shown-card card'/>"];
    }, [1, ""]);
    $("#game-shown-cards").html(html[1]);
    $(".shown-card").on("click", function(){
        card = parseInt($(this).attr("id").split("-")[1]);
        send({type: "play_to", where: "shown", card: card});
    });
}

function update_hand(hand) {
    var html = hand.reduce(function(acc, card) {
        return [acc[0] + 1, acc[1] + "<img src='" + card + "' id='card-" + acc[0] + "' class='hand-card card'/>"];
    }, [1, ""]);
    $("#game-hand-cards").html(html[1]);
    $(".hand-card").on("click", function(){
        card = parseInt($(this).attr("id").split("-")[1]);
        send({type: "play_from", card: card});
    });
}

function update_playing_card(card) {
    if (card != undefined) {
        $("#playing-card").attr("src", card);
    } else {
        $("#playing-card").attr("src", backside());
    }
}

function update_deck(deck) {
    $("#game-deck span").html(deck);
}

function backside() {
    return "/img/cards/" + deck_style + "/backside.svg";
}

function update_captured(players, captured) {
    var html = players.reduce(function (acc, player) {
        var player_name = player.username;
        acc += "<div class='captured-cards' id='captured-cards-" + player_name + "'>";
        acc += "<h3>" + player_name + "(" + player.captured_cards + ")</h3>";
        if (captured[player_name] != undefined) {
            var card = captured[player_name];
            acc += "<img class='card' src='" + card + "'/>";
        } else {
            acc += "<img class='card' src='" + backside() + "'/>";
        }
        acc += "</div>";
        return acc;
    }, "");
    $("#game-captured-cards").html(html);
    $(".captured-cards").on("click", function(){
        var card = $(this).attr("id").split("-")[2];
        send({type: "play_to", where: "player", card: card});
    });
}

function update_turn(turn) {
    $("#game-turn strong").html(turn);
}

function update_game(data) {
    update_turn(data.turn);
    update_captured(data.players, data.captured);
    update_shown_card(data.shown);
    update_hand(data.hand);
    update_deck(data.deck);
    update_playing_card(data.playing);
    $("#game-msg").html("");
}

function update_player(username) {
    var slug = slugify(username);
    $("#modal-players").append("<li id='" + slug + "'>" + username + "</li>");
    if ($("#modal-players li").length >= 2) {
        $("#deal").removeClass("disabled");
    } else {
        $("#deal").addClass("disabled");
    }
}

function clear_player(username) {
    var slug = slugify(username);
    $("#" + slug).remove();
}

function clean_players() {
    $("#modal-players").html("");
}

function get_url_base(new_uri = "/") {
    var url = new URL(document.URL);
    url.pathname = new_uri;
    return url.toString();
}

function set_game_id(id) {
    game_id = id;
    var web_url = get_url_base("/" + game_id);
    var qr_url = get_url_base("/qr/" + game_id);
    $("#modal-players-url").attr("href", web_url);
    $("#modal-players-url").html(web_url);
    $("#modal-players-url-img").attr("src", qr_url);
    history.pushState({id: game_id}, "Zero Game", web_url);
}

$(document).ready(function(){
    connect();
    $("#username").on("keydown", function(event) {
        var keyCode = event.keyCode || event.which;
        if (keyCode == 13) {
            $("#join").trigger("click");
            return false;
        }
    });
    $("#join").on("click", function(event) {
        event.preventDefault();
        var user = $("#username").val();
        $("#onBoardingModal").modal('hide');
        $("#dealingModal").modal('show');
        $("#bot-name").focus();
        username = user;
        send({type: "join", name: game_id, username: user});
    });
    $("#deal").on("click", function(event) {
        event.preventDefault();
        send({type: "deal"});
    });
    $("#game-pass").on("click", function(event) {
        event.preventDefault();
        send({type: "pass"});
    });
    $("#deck-napoletane").on("click", function(event) {
        event.preventDefault();
        var old_deck_style = deck_style;
        deck_style = "napoletane";
        change_deck_style(old_deck_style);
        send({type: "deck_style", name: deck_style});
    });
    $("#game-over-new").on("click", function(event){
        event.preventDefault();
        send({type: "stop"});
        location.href = get_url_base();
    });
    $("#game-over-restart").on("click", function(event){
        event.preventDefault();
        send({type: "restart"});
        $("#gameOverModal").modal('hide');
    });
});

// from: https://gist.github.com/hagemann/382adfc57adbd5af078dc93feef01fe1#file-slugify-js
function slugify(string) {
    const a = 'àáäâãåăæąçćčđďèéěėëêęğǵḧìíïîįłḿǹńňñòóöôœøṕŕřßşśšșťțùúüûǘůűūųẃẍÿýźžż·/_,:;"\''
    const b = 'aaaaaaaaacccddeeeeeeegghiiiiilmnnnnooooooprrsssssttuuuuuuuuuwxyyzzz--------'
    const p = new RegExp(a.split('').join('|'), 'g')
  
    return string.toString().toLowerCase()
      .replace(/\s+/g, '-') // Replace spaces with -
      .replace(p, c => b.charAt(a.indexOf(c))) // Replace special characters
      .replace(/&/g, '-and-') // Replace & with 'and'
      .replace(/[^\w\-]+/g, '') // Remove all non-word characters
      .replace(/\-\-+/g, '-') // Replace multiple - with single -
      .replace(/^-+/, '') // Trim - from start of text
      .replace(/-+$/, '') // Trim - from end of text
}
