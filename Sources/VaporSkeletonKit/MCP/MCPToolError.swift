import MCP

/// Un fallo a nivel de dominio lanzado por una ``MCPTool``.
///
/// Distinguir estos casos permite que `MCPToolDispatch` reporte cada uno como un
/// resultado de herramienta estructurado con `isError: true` que el modelo llamador
/// puede realmente leer y ante el que puede reaccionar, en lugar de una única cadena de
/// error genérica.
public enum MCPToolError: Error, Sendable {
    /// Los argumentos pasados a la herramienta faltaban, tenían un formato incorrecto o
    /// eran inválidos por otro motivo (p. ej. un id que no es un UUID, o un campo
    /// obligatorio vacío).
    case invalidArgument(String)

    /// El recurso solicitado no existe (p. ej. no hay ningún registro con el id dado).
    case notFound(String)

    /// La base de datos subyacente no pudo completar la operación.
    case database(String)

    /// Ocurrió un fallo inesperado que no encaja en el resto de casos.
    case internalError(String)

    /// Una etiqueta corta y legible por máquina para este caso de error, incluida en la
    /// salida estructurada para que los llamadores puedan bifurcar su lógica sin tener
    /// que parsear el texto del mensaje.
    var kind: String {
        switch self {
        case .invalidArgument: return "invalid_argument"
        case .notFound: return "not_found"
        case .database: return "database_error"
        case .internalError: return "internal_error"
        }
    }

    /// El mensaje legible por humanos que describe este error.
    var message: String {
        switch self {
        case .invalidArgument(let message), .notFound(let message), .database(let message),
            .internalError(let message):
            return message
        }
    }

    /// Convierte este error en un resultado de llamada a herramienta con
    /// `isError: true`, de modo que el modelo llamador lo vea como una respuesta normal
    /// de herramienta (aunque sin éxito) en lugar de un error fatal de transporte.
    var callToolResult: CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            structuredContent: .object(["error": .string(kind), "message": .string(message)]),
            isError: true
        )
    }
}
