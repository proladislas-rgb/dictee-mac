import Foundation

enum MotsDuQuotidien {
    /// Mots du quotidien (pliés) : jamais « inhabituels » (relecture, phrase courte) et jamais retenus comme expression personnelle.
    static let courants: Set<String> = {
        let l = "le la les un une des du de d l au aux et ou mais donc or ni car que qui quoi dont où ce cet cette ces ca ça cela ceci il elle on ils elles nous vous je tu me te se moi toi lui leur leurs mon ma mes ton ta tes son sa ses notre votre nos vos est es suis sommes etes sont ete etre ai as avons avez ont avoir fait faire va vas vais vont aller veux veut peux peut doit dois faut pas ne plus rien tout tous toute toutes tres trop bien bon bonne mal oui non ouais ok okay merci salut bonjour bonsoir hello hey alors puis ensuite apres avant encore deja jamais toujours aussi comme si en y a à dans sur sous avec sans pour par chez vers entre depuis pendant demain hier aujourd hui maintenant tout suite tard bientot ici la là voila voici peu beaucoup assez vraiment juste justement peut etre d accord c est j ai the a an is are was be to of and in it you i that this for on with not yes no thanks please".split(separator: " ")
        return Set(l.map { ClePhonetique.plier(String($0)) })
    }()

}
