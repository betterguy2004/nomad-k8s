<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class HealthController extends Controller
{
    public function health(): JsonResponse
    {
        $dbOk = true;
        try {
            DB::connection()->getPdo();
        } catch (\Exception $e) {
            $dbOk = false;
        }

        $status = $dbOk ? 'ok' : 'error';
        $httpCode = $dbOk ? 200 : 503;

        return response()->json([
            'status' => $status,
            'database' => $dbOk ? 'ok' : 'error',
            'timestamp' => now()->toIso8601String(),
        ], $httpCode);
    }

    public function status(): JsonResponse
    {
        return response()->json(['status' => 'ok']);
    }
}
