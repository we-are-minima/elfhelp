import SwiftUI

/// Draft pending controller details, retention configuration and a working deletion route.
/// Keep the public policy and App Store privacy answers aligned with the actual service.
private let privacySections: [(title: String, body: String)] = [
    ("Responsable y contacto", "Responsable: Marina López García. Dirección: Calle José Hierro 9, San Sebastián de los Reyes, Madrid (España). Contacto de privacidad: hello@weareminima.com."),
    ("Qué información utilizamos", "Elf Help está dirigida a personas adultas que preparan actividades familiares. No solicita nombres, edades ni fotografías de menores, ni pide nombre, email o contraseña para utilizar la app. En el iPhone se guardan el número de elfos, las preferencias, el calendario de travesuras, sus estados y la configuración de los avisos."),
    ("Datos enviados a Supabase", "La app crea automáticamente una sesión sin nombre ni email en Supabase. Esa sesión tiene un identificador persistente: no significa que los datos sean completamente anónimos. Se envían los identificadores de las travesuras, sus fechas asignadas, si están pendientes, hechas o no realizadas, la respuesta a la pregunta diaria y la fecha de actualización. Las credenciales de sesión se guardan en el llavero de iOS. Supabase también sirve el catálogo y las imágenes; estas conexiones requieren transmitir información técnica, como la dirección IP."),
    ("Para qué se utilizan", "Las preferencias locales permiten personalizar la experiencia y programar los avisos de preparación. La copia del calendario en Supabase permite conocer qué travesuras se eligen y sus resultados para mejorar el contenido. La app no incorpora herramientas de seguimiento publicitario entre aplicaciones. Base jurídica de cada tratamiento: [pendiente de confirmar antes de publicar, especialmente la copia del calendario para analizar su uso]."),
    ("Proveedores y enlaces externos", "Utilizamos Supabase para alojar el catálogo, las imágenes, las sesiones y los registros descritos. Alojamiento y transferencias internacionales: [confirmar la región del proyecto y las garantías aplicables con el proveedor]. Si decides compartir una travesura, los datos que compartas se entregan a la aplicación que elijas. Los sitios web de las promociones y los servicios externos aplican sus propias políticas."),
    ("Avisos", "Los recordatorios se programan localmente y requieren tu permiso. Puedes desactivarlos desde Elf Help o desde los ajustes de notificaciones de iOS."),
    ("Conservación y borrado", "Las preferencias y el calendario permanecen en el dispositivo mientras se conserven los datos de la app. Desinstalarla no elimina por sí solo los registros de Supabase, y las credenciales del llavero pueden persistir. Plazo de conservación en el servidor: [pendiente de confirmar y aplicar]. Canal y procedimiento de eliminación de la sesión y sus datos: [pendientes de habilitar antes de publicar]. Actualmente no existe un botón de borrado en la app."),
    ("Tus derechos", "Según la normativa aplicable, puedes solicitar acceso, rectificación, supresión, limitación, portabilidad u oposición al tratamiento de tus datos, y retirar el consentimiento cuando sea la base utilizada. Para ejercerlos, escribe a hello@weareminima.com. También puedes presentar una reclamación ante la autoridad de protección de datos competente, como la AEPD en España."),
    ("Cambios en esta política", "Actualizaremos esta política cuando cambien los datos utilizados, las finalidades o los proveedores. La versión publicada indicará su fecha de actualización.")
]

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section {
                Text("Borrador · 25 de noviembre de 2026")
                    .font(.headline)
                Text("Pendiente de completar y revisar antes de publicar en App Store. Los campos entre corchetes no son información definitiva.")
                    .font(.subheadline)
            }
            ForEach(privacySections.indices, id: \.self) { index in
                Section(privacySections[index].title) {
                    Text(privacySections[index].body)
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacidad")
        .navigationBarTitleDisplayMode(.inline)
    }
}
