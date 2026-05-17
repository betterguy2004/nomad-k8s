<?php

namespace Tests\Feature;

use Tests\TestCase;

class HealthTest extends TestCase
{
    public function test_welcome_page_returns_200(): void
    {
        $response = $this->get('/');

        $response->assertStatus(200);
        $response->assertSee('Laravel App');
    }

    public function test_health_endpoint_returns_json(): void
    {
        $response = $this->get('/health');

        $response->assertStatus(200);
        $response->assertJsonStructure(['status', 'database', 'timestamp']);
    }

    public function test_api_status_returns_ok(): void
    {
        $response = $this->get('/api/status');

        $response->assertStatus(200);
        $response->assertJson(['status' => 'ok']);
    }
}
