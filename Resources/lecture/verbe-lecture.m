// Verbe : programme d'aide « lecture en cours ».
//
// Depuis macOS 15.4, MediaRemote (le service qui sait ce qui joue sur le Mac) refuse de répondre aux apps tierces :
// seuls les processus dont l'identifiant commence par « com.apple. » sont servis. Ce petit module natif est donc chargé
// par /usr/bin/perl (binaire système signé Apple, voir lanceur.pl), qui fournit l'identifiant demandé. Le module n'est PAS
// dans Verbe : c'est un processus à part, lancé seulement quand le réglage « Afficher la lecture en cours » est actif.
//
// Protocole (lignes JSON, une par ligne) :
//   sortie : {"t":"etat", ...}   ce qui joue (titre, artiste, app, durée, position, lecture, image) ; émis seulement
//                                quand quelque chose change, jamais en boucle
//            {"t":"rien"}        plus rien en cours
//            {"t":"pret"}        démarrage réussi ; {"t":"echec","raison":"..."} impossible de lire MediaRemote
//   entrée : {"cmd":"play"|"pause"|"toggle"|"next"|"prev"|"seek","pos":secondes}
//            la fin de l'entrée (Verbe a quitté) arrête le programme.
// Aucune donnée n'est écrite ailleurs que sur la sortie, hors l'image du morceau, déposée dans $VERBE_LECTURE_DIR (0600).
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>
#import <sys/stat.h>

typedef void (^MRInfoBloc)(CFDictionaryRef info);
typedef void (^MRBoolBloc)(Boolean b);
typedef void (^MRIntBloc)(int n);
typedef void (^MRChaineBloc)(CFStringRef s);
static void (*MRGetInfo)(dispatch_queue_t, MRInfoBloc);
static void (*MRGetIsPlaying)(dispatch_queue_t, MRBoolBloc);
static void (*MRGetPID)(dispatch_queue_t, MRIntBloc);
static void (*MRGetDisplayID)(dispatch_queue_t, MRChaineBloc);
static void (*MRRegister)(dispatch_queue_t);
static Boolean (*MRSendCommand)(int, CFDictionaryRef);
static void (*MRSetElapsed)(double);

static NSString *gDossierImages;
static NSString *gDerniereLigne;
static NSString *gDernierHash;
static NSString *gDernierChemin;
static dispatch_source_t gMinuterieRaffraichir;   // regroupe les rafales de notifications (un seul rafraîchissement)
static BOOL gRafraichissementEnCours, gRafraichirEncore;
static NSDate *gDebutSansEvenement;

static void ecrireLigne(NSDictionary *d) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
    if (!json) return;
    NSString *ligne = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    if ([ligne isEqualToString:gDerniereLigne]) return;   // rien n'a changé : rien n'est écrit
    gDerniereLigne = ligne;
    NSMutableData *sortie = [json mutableCopy];
    [sortie appendBytes:"\n" length:1];
    fwrite(sortie.bytes, 1, sortie.length, stdout);
    fflush(stdout);
}

/// Valeur d'une constante de chaîne exportée par un framework (ex. kMRMediaRemoteNowPlayingInfoTitle), ou nil.
static NSString *constanteChaine(const char *nom) {
    void *p = dlsym(RTLD_DEFAULT, nom);
    return p ? (__bridge NSString *)*(void **)p : nil;
}

/// Valeur d'une clé du dictionnaire d'infos : la constante exportée par le framework, sinon son nom littéral.
static id valeur(NSDictionary *info, const char *constante) {
    NSString *cle = constanteChaine(constante) ?: [NSString stringWithUTF8String:constante];
    id v = info[cle];
    return v == [NSNull null] ? nil : v;
}

/// Dépose l'image (si elle a changé) dans le dossier d'images ; renvoie son chemin, ou nil.
static NSString *deposerImage(NSData *donnees, NSString *mime) {
    if (![donnees isKindOfClass:[NSData class]] || donnees.length == 0 || !gDossierImages) return nil;
    // empreinte simple : longueur + quelques octets (suffit à voir un changement d'image)
    const uint8_t *o = donnees.bytes;
    NSString *hash = [NSString stringWithFormat:@"%lu-%02x%02x%02x%02x", (unsigned long)donnees.length,
                      o[0], o[donnees.length / 3], o[donnees.length / 2], o[donnees.length - 1]];
    if ([hash isEqualToString:gDernierHash] && gDernierChemin) return gDernierChemin;
    NSString *ancien = gDernierChemin;
    NSString *chemin = [gDossierImages stringByAppendingPathComponent:[NSString stringWithFormat:@"image-%@.%@", hash, [mime isEqualToString:@"image/png"] ? @"png" : ([mime isEqualToString:@"image/jpeg"] ? @"jpg" : @"img")]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:chemin]) {
        int fd = open(chemin.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd < 0) return nil;
        write(fd, donnees.bytes, donnees.length);
        close(fd);
    }
    gDernierHash = hash; gDernierChemin = chemin;
    if (ancien && ![ancien isEqualToString:chemin]) [[NSFileManager defaultManager] removeItemAtPath:ancien error:nil];
    return chemin;
}

/// Un nombre fini seulement (un direct annonce parfois une durée infinie, que JSON ne sait pas écrire).
static NSNumber *nombre(id v) { return [v isKindOfClass:[NSNumber class]] && isfinite([v doubleValue]) ? v : nil; }
static NSString *texte(id v) { return [v isKindOfClass:[NSString class]] && [(NSString *)v length] ? v : nil; }

/// Interroge MediaRemote (infos, lecture, app) et écrit une ligne. Une seule interrogation à la fois.
static void rafraichir(void) {
    if (gRafraichissementEnCours) { gRafraichirEncore = YES; return; }
    gRafraichissementEnCours = YES;
    dispatch_queue_t q = dispatch_get_main_queue();
    __block NSDictionary *info = nil;
    __block BOOL joue = NO;
    __block int pid = 0;
    __block NSString *bundle = nil;
    dispatch_group_t g = dispatch_group_create();
    dispatch_group_enter(g);
    MRGetInfo(q, ^(CFDictionaryRef d) { info = d ? [(__bridge NSDictionary *)d copy] : nil; dispatch_group_leave(g); });
    dispatch_group_enter(g);
    MRGetIsPlaying(q, ^(Boolean b) { joue = b; dispatch_group_leave(g); });
    dispatch_group_enter(g);
    MRGetPID(q, ^(int n) { pid = n; dispatch_group_leave(g); });
    dispatch_group_enter(g);
    MRGetDisplayID(q, ^(CFStringRef s) { bundle = s ? [(__bridge NSString *)s copy] : nil; dispatch_group_leave(g); });
    dispatch_group_notify(g, q, ^{
        gRafraichissementEnCours = NO;
        if (getenv("VERBE_LECTURE_DEBUG") && info) {   // mise au point : les clés reçues et leurs valeurs courtes, sur la sortie d'erreur
            for (NSString *k in [info.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                NSString *v = [NSString stringWithFormat:@"%@", info[k]];
                fprintf(stderr, "  %s = %s\n", k.UTF8String, (v.length > 90 ? [[v substringToIndex:90] stringByAppendingString:@"…"] : v).UTF8String);
            }
            fprintf(stderr, "  app=%s pid=%d joue=%d\n", bundle.UTF8String ?: "-", pid, joue);
        }
        NSString *titre = texte(valeur(info, "kMRMediaRemoteNowPlayingInfoTitle"));
        if (!info || (!titre && !bundle)) {
            ecrireLigne(@{@"t": @"rien"});
        } else {
            NSMutableDictionary *e = [NSMutableDictionary dictionary];
            e[@"t"] = @"etat";
            e[@"joue"] = @(joue);
            if (titre) e[@"titre"] = titre;
            NSString *artiste = texte(valeur(info, "kMRMediaRemoteNowPlayingInfoArtist"));
            NSString *album = texte(valeur(info, "kMRMediaRemoteNowPlayingInfoAlbum"));
            if (artiste) e[@"artiste"] = artiste;
            if (album) e[@"album"] = album;
            if (bundle) e[@"app"] = bundle;
            if (pid > 0) e[@"pid"] = @(pid);
            NSNumber *duree = nombre(valeur(info, "kMRMediaRemoteNowPlayingInfoDuration"));
            NSNumber *ecoule = nombre(valeur(info, "kMRMediaRemoteNowPlayingInfoElapsedTime"));
            NSNumber *vitesse = nombre(valeur(info, "kMRMediaRemoteNowPlayingInfoPlaybackRate"));
            id horodatage = valeur(info, "kMRMediaRemoteNowPlayingInfoTimestamp");
            if (duree && duree.doubleValue > 0) e[@"duree"] = duree;
            if (ecoule) {
                e[@"pos"] = ecoule;
                // l'instant (secondes depuis 1970) auquel `pos` était exact : Verbe avance seul à partir de là
                e[@"depuis"] = [horodatage isKindOfClass:[NSDate class]] ? @([(NSDate *)horodatage timeIntervalSince1970]) : @([[NSDate date] timeIntervalSince1970]);
            }
            e[@"vitesse"] = vitesse ?: @(joue ? 1 : 0);
            NSString *image = deposerImage(valeur(info, "kMRMediaRemoteNowPlayingInfoArtworkData"), texte(valeur(info, "kMRMediaRemoteNowPlayingInfoArtworkMIMEType")));
            if (image) e[@"image"] = image;
            ecrireLigne(e);
        }
        if (gRafraichirEncore) { gRafraichirEncore = NO; rafraichir(); }
    });
}

/// Les notifications arrivent par rafales (titre, image, durée, lecture…) : un seul rafraîchissement 120 ms après la dernière.
static void planifierRafraichissement(void) {
    dispatch_source_set_timer(gMinuterieRaffraichir, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), DISPATCH_TIME_FOREVER, 20 * NSEC_PER_MSEC);
}

static void traiterCommande(NSDictionary *c) {
    NSString *cmd = c[@"cmd"];
    if (![cmd isKindOfClass:[NSString class]]) return;
    // numéros de commandes de MediaRemote (MRMediaRemoteCommand) : 0 lecture, 1 pause, 2 bascule, 4 suivant, 5 précédent
    int numero = -1;
    if ([cmd isEqualToString:@"play"]) numero = 0;
    else if ([cmd isEqualToString:@"pause"]) numero = 1;
    else if ([cmd isEqualToString:@"toggle"]) numero = 2;
    else if ([cmd isEqualToString:@"next"]) numero = 4;
    else if ([cmd isEqualToString:@"prev"]) numero = 5;
    if (numero >= 0) { MRSendCommand(numero, NULL); }
    else if ([cmd isEqualToString:@"seek"] && [c[@"pos"] isKindOfClass:[NSNumber class]]) { MRSetElapsed([c[@"pos"] doubleValue]); }
    else return;
    planifierRafraichissement();   // l'état (lecture, position) a pu changer
}

/// Lit les commandes sur l'entrée standard ; la fin de l'entrée (Verbe a quitté ou nous a fermés) arrête le programme.
static void lireLesCommandes(void) {
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    static NSMutableData *tampon;
    tampon = [NSMutableData data];
    dispatch_source_set_event_handler(src, ^{
        uint8_t buf[4096];
        ssize_t n = read(STDIN_FILENO, buf, sizeof buf);
        if (n <= 0) { _exit(0); }
        [tampon appendBytes:buf length:(NSUInteger)n];
        for (;;) {
            NSRange r = [tampon rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, tampon.length)];
            if (r.location == NSNotFound) break;
            NSData *ligne = [tampon subdataWithRange:NSMakeRange(0, r.location)];
            [tampon replaceBytesInRange:NSMakeRange(0, r.location + 1) withBytes:NULL length:0];
            id obj = ligne.length ? [NSJSONSerialization JSONObjectWithData:ligne options:0 error:nil] : nil;
            if ([obj isKindOfClass:[NSDictionary class]]) traiterCommande(obj);
        }
        if (tampon.length > 65536) [tampon setLength:0];
    });
    dispatch_resume(src);
    static dispatch_source_t garde; garde = src; (void)garde;
}

static void echec(NSString *raison) {
    ecrireLigne(@{@"t": @"echec", @"raison": raison});
    _exit(2);
}

/// Point d'entrée appelé par lanceur.pl (convention des modules Perl : deux arguments ignorés). Ne rend jamais la main.
void verbe_lecture_main(void *interpreteur, void *cv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOFBF, 1 << 16);
        gDossierImages = [NSProcessInfo processInfo].environment[@"VERBE_LECTURE_DIR"];
        if (gDossierImages) mkdir(gDossierImages.fileSystemRepresentation, 0700);

        void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!h) echec(@"MediaRemote introuvable");
        MRGetInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        MRGetIsPlaying = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        MRGetPID = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID");
        MRGetDisplayID = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationDisplayID");
        MRRegister = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
        MRSendCommand = dlsym(h, "MRMediaRemoteSendCommand");
        MRSetElapsed = dlsym(h, "MRMediaRemoteSetElapsedTime");
        if (!MRGetInfo || !MRGetIsPlaying || !MRGetPID || !MRGetDisplayID || !MRRegister || !MRSendCommand || !MRSetElapsed)
            echec(@"fonctions MediaRemote manquantes");

        gMinuterieRaffraichir = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(gMinuterieRaffraichir, ^{ rafraichir(); });
        dispatch_source_set_timer(gMinuterieRaffraichir, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
        dispatch_resume(gMinuterieRaffraichir);

        MRRegister(dispatch_get_main_queue());
        const char *notifs[] = {"kMRMediaRemoteNowPlayingInfoDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                                "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"};
        for (size_t i = 0; i < sizeof notifs / sizeof *notifs; i++) {
            NSString *nom = constanteChaine(notifs[i]);
            if (!nom) continue;
            [[NSNotificationCenter defaultCenter] addObserverForName:nom object:nil queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *n) { planifierRafraichissement(); }];
        }
        lireLesCommandes();
        ecrireLigne(@{@"t": @"pret"});
        gDerniereLigne = nil;
        rafraichir();   // état initial
        CFRunLoopRun();
    }
    _exit(0);
}
