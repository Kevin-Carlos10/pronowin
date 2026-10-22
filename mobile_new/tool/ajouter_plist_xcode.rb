# Ajoute GoogleService-Info.plist au projet Xcode, s'il n'y est pas déjà.
#
# Pourquoi ce script existe
# ─────────────────────────
# Le fichier peut très bien être sur le disque sans que Xcode le connaisse :
# `project.pbxproj` ne le référençait nulle part. Dans ce cas il n'est pas copié
# dans le bundle de l'app, et Firebase échoue au démarrage avec
# « Could not locate configuration file: 'GoogleService-Info.plist' ».
#
# En temps normal on le fait à la souris, en glissant le fichier dans Xcode.
# Le projet étant développé sous Windows, personne ne peut effectuer ce geste :
# il faut donc que la CI le fasse, à chaque build, de façon reproductible.
#
# Le script est idempotent : relancé sur un projet déjà correct, il ne fait
# rien et sort en 0. Il peut donc rester dans le pipeline sans condition.
#
#   ruby tool/ajouter_plist_xcode.rb        (depuis mobile_new/)

require 'xcodeproj'

CHEMIN_PROJET = 'ios/Runner.xcodeproj'
NOM_FICHIER   = 'GoogleService-Info.plist'
NOM_CIBLE     = 'Runner'

abort "Projet introuvable : #{CHEMIN_PROJET}" unless Dir.exist?(CHEMIN_PROJET)
abort "Fichier absent : ios/#{NOM_CIBLE}/#{NOM_FICHIER} — la variable " \
      "GOOGLE_SERVICE_INFO_PLIST a-t-elle été décodée ?" \
      unless File.exist?("ios/#{NOM_CIBLE}/#{NOM_FICHIER}")

projet = Xcodeproj::Project.open(CHEMIN_PROJET)

cible = projet.targets.find { |t| t.name == NOM_CIBLE }
abort "Cible « #{NOM_CIBLE} » introuvable." if cible.nil?

groupe = projet.main_group[NOM_CIBLE]
abort "Groupe « #{NOM_CIBLE} » introuvable." if groupe.nil?

# Déjà référencé ? On regarde le groupe ET la phase de copie : un fichier peut
# figurer dans l'arborescence sans être copié dans le bundle, ce qui produit
# exactement la même panne que s'il était absent.
reference = groupe.files.find { |f| f.display_name == NOM_FICHIER }

if reference.nil?
  reference = groupe.new_reference(NOM_FICHIER)
  puts "  référence ajoutée à l'arborescence"
else
  puts "  référence déjà présente"
end

deja_copie = cible.resources_build_phase.files.any? do |f|
  f.file_ref && f.file_ref.display_name == NOM_FICHIER
end

if deja_copie
  puts "  déjà dans « Copy Bundle Resources »"
else
  cible.resources_build_phase.add_file_reference(reference)
  puts "  ajouté à « Copy Bundle Resources »"
end

projet.save

# Relecture depuis le disque : on vérifie ce qui a été écrit, pas ce qu'on
# croit avoir écrit.
verif = Xcodeproj::Project.open(CHEMIN_PROJET)
ok = verif.targets.find { |t| t.name == NOM_CIBLE }
             .resources_build_phase.files.any? do |f|
  f.file_ref && f.file_ref.display_name == NOM_FICHIER
end

abort "ÉCHEC : #{NOM_FICHIER} n'est toujours pas copié dans le bundle." unless ok
puts "  vérifié : #{NOM_FICHIER} sera embarqué dans l'app"
