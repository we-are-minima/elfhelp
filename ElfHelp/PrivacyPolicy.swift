import SwiftUI

/// Same content as the public policy page. Keep both, and the App Store privacy answers, aligned with the service.
private let privacySections: [(title: String, body: String)] = [
    ("Responsable y contacto", "Responsable: Marina López García. Madrid (España). Contacto de privacidad: hello@weareminima.com."),
    ("Qué información utilizamos", "Elf Help está dirigida a personas adultas que preparan actividades familiares. No solicita nombres, edades ni fotografías de menores, ni pide nombre, email o contraseña para utilizar la app. En el iPhone se guardan el número de elfos, las preferencias, el calendario de travesuras, sus estados y la configuración de los avisos."),
    ("Datos enviados a nuestro servidor", "La app crea automáticamente una sesión sin nombre ni email. Esa sesión tiene un identificador persistente: no significa que los datos sean completamente anónimos. Se envían los identificadores de las travesuras, sus fechas asignadas, si están pendientes, hechas o no realizadas, la respuesta a la pregunta diaria y la fecha de actualización. Las credenciales de sesión se guardan en el llavero de iOS. Al descargar el catálogo y las imágenes se transmite información técnica, como la dirección IP."),
    ("Para qué se utilizan y base jurídica", "Mostrar el catálogo, las imágenes y tu calendario: prestarte el servicio que solicitas al usar la app. Conocer qué travesuras se eligen y sus resultados para mejorar el contenido: interés legítimo, con datos que no te identifican directamente. Avisos de preparación: tu consentimiento, que das al activarlos y puedes retirar cuando quieras. La app no incluye publicidad, no vende datos ni usa herramientas de seguimiento entre aplicaciones."),
    ("Proveedores y enlaces externos", "Utilizamos Supabase para alojar el catálogo, las imágenes, las sesiones y la copia del calendario. Actúa como encargado del tratamiento y los datos se alojan en la Unión Europea (Fráncfort, Alemania). Supabase tiene sede en Estados Unidos; cualquier acceso desde fuera del Espacio Económico Europeo se ampara en las cláusulas contractuales tipo de la Comisión Europea. Si decides compartir una travesura, los datos que compartas se entregan a la aplicación que elijas. Los sitios web de las promociones y los servicios externos aplican sus propias políticas."),
    ("Avisos", "Los recordatorios se programan localmente y requieren tu permiso. Puedes desactivarlos desde Elf Help o desde los ajustes de notificaciones de iOS."),
    ("Conservación", "Las preferencias y el calendario permanecen en el dispositivo mientras tengas la app instalada; las credenciales del llavero pueden persistir tras desinstalarla. En el servidor, la copia del calendario de cada edición se elimina como máximo 12 meses después de que termine esa edición (el 24 de diciembre)."),
    ("Tus derechos", "Puedes solicitar acceso, rectificación, supresión, limitación, portabilidad u oposición al tratamiento de tus datos, y retirar tu consentimiento, escribiendo a hello@weareminima.com. Como no pedimos nombre ni email, puede que necesitemos datos de tu uso de la app para localizar tu sesión; si no podemos identificarla te lo diremos, y tus datos se borrarán igualmente al cumplirse el plazo de conservación. También puedes reclamar ante la Agencia Española de Protección de Datos (aepd.es)."),
    ("Cambios en esta política", "Actualizaremos esta política cuando cambien los datos utilizados, las finalidades o los proveedores. Última actualización: 25 de noviembre de 2026.")
]

struct PrivacyPolicyView: View {
    var body: some View {
        List {
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
