<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Annotation\Route;

class UserController extends AbstractController
{
    /**
     * Retrieve a list of all registered users in the system.
     */
    #[Route('/api/1/users/list', name: 'get_all_users', methods: ['GET'])]
    public function getAllUsers(): JsonResponse
    {
        return $this->json(['users' => []]);
    }

    /**
     * Retrieve a list of subscribed users in the system.
     */
    #[Route('/api/1/subscribers/list', name: 'get_all_subscribers', methods: ['GET'])]
    public function getAllSubscribers(): JsonResponse
    {
        return $this->json(['users' => []]);
    }
}
