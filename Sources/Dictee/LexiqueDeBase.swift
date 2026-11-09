import Foundation

/// Quelques mots difficiles que Whisper écrit mal, dans plusieurs langues : villes et quartiers d'Afrique de l'Ouest et centrale, mots
/// d'ailleurs, marques et outils. Aucun nom de personne. Ils entrent dans le lexique en dernier (fréquence 1) ; ceux que le correcteur
/// orthographique connaît déjà sont retirés comme les autres.
enum LexiqueDeBase {
    static let mots: [String] = [
        // Côte d'Ivoire
        "Abidjan", "Yamoussoukro", "Bouaké", "Korhogo", "Daloa", "San-Pédro", "Grand-Bassam", "Cocody", "Yopougon", "Treichville",
        "Marcory", "Koumassi", "Adjamé", "Abobo", "Attécoubé", "Port-Bouët", "Bingerville", "Anyama", "Songon", "Divo", "Gagnoa",
        "Odienné", "Ferkessédougou", "Attiéké", "Alloco", "Garba", "Kedjenou", "Foutou", "Gouro", "Baoulé", "Dioula", "Sénoufo",
        // Afrique de l'Ouest et du Centre
        "Ouagadougou", "Bobo-Dioulasso", "Dakar", "Bamako", "Cotonou", "Porto-Novo", "Niamey", "Libreville", "Brazzaville", "Kinshasa",
        "Douala", "Yaoundé", "Nouakchott", "Ndjamena", "Conakry", "Freetown", "Monrovia", "Accra", "Kumasi", "Lagos", "Abuja",
        "Ibadan", "Kaolack", "Ziguinchor", "Saint-Louis", "Tombouctou", "Ségou", "Sikasso", "Lomé", "Kara", "Malabo", "Praia",
        // Afrique de l'Est, du Nord, Madagascar
        "Antananarivo", "Nairobi", "Mombasa", "Addis-Abeba", "Kigali", "Kampala", "Dar es Salaam", "Zanzibar", "Maputo", "Windhoek",
        "Marrakech", "Casablanca", "Rabat", "Fès", "Tanger", "Agadir", "Tunis", "Sfax", "Alger", "Oran", "Constantine",
        // Espagnol, portugais, italien
        "Guadalajara", "Chihuahua", "Zaragoza", "Valladolid", "Tenerife", "Fuerteventura", "Lanzarote", "Oaxaca", "Cartagena", "Medellín",
        "Barranquilla", "Montevideo", "Asunción", "Florianópolis", "Fortaleza", "Salvador", "Lisboa", "Algarve", "Sintra", "Gnocchi",
        // Anglais et autres
        "Tbilisi", "Reykjavik", "Ljubljana", "Wrocław", "Gdańsk", "Edinburgh", "Worcestershire", "Leicester", "Gloucester", "Thames",
        "Seoul", "Guangzhou", "Shenzhen", "Hanoi", "Jakarta", "Kuala Lumpur", "Bangalore", "Hyderabad", "Chennai", "Colombo",
        // Marques, outils, jargon
        "Kubernetes", "PostgreSQL", "Tailwind", "Vercel", "Supabase", "Anthropic", "Airtable", "Figma", "Qonto", "Pennylane",
        "Doctolib", "BlaBlaCar", "Deliveroo", "Zapier", "Pipedrive", "Hubspot", "Salesforce", "Typeform", "Calendly", "Slack",
        "Notion", "Linear", "Stripe", "Shopify", "Webflow", "Squarespace", "Cloudflare", "Terraform", "Ansible", "Grafana",
        "Prometheus", "Elasticsearch", "MongoDB", "Redis", "RabbitMQ", "Kafka", "GraphQL", "TypeScript", "JavaScript", "Xcode",
        "SwiftUI", "WebSocket", "OAuth", "Nginx", "Docker", "Homebrew", "Zsh", "GitHub", "GitLab", "Bitbucket",
        // Mots composés et termes d'ailleurs
        "bas-carbone", "auto-entrepreneur", "freemium", "onboarding", "benchmark", "feedback", "workflow", "roadmap", "dashboard", "backlog",
    ]
}
